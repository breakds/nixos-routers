{ pkgs, lib, ... }:

{
  nixpkgs.overlays = [
    (final: prev: let
      # CVE-2026-111943: distrust the compromised eMudhra intermediates.
      # Keep Go private to avoid rebuilding libcap and unrelated packages.
      # Remove these backports once nixpkgs supplies the fixed versions.
      patchedGo = if prev.lib.versionAtLeast prev.go_1_26.version "1.26.10" then
        prev.go_1_26
      else
        prev.go_1_26.overrideAttrs (_: {
          version = "1.26.10";
          src = prev.fetchurl {
            url = "https://go.dev/dl/go1.26.10.src.tar.gz";
            hash = "sha256-/WPog7ovK/ypPBZGsx6+9j4rHk0rMXyXidl2po2B828=";
          };
        });
    in {
      # This nixpkgs pin already supplies Go 1.27.3 for Tailscale.
      tailscale = if prev.lib.versionAtLeast prev.tailscale.version "1.104.2" then
        prev.tailscale
      else
        final.callPackage ../nix/pkgs/tailscale/package.nix {
          inherit (prev) buildGo127Module;
        };

      # AdGuard downloads blocklists and can use DNS-over-HTTPS upstreams.
      adguardhome = prev.adguardhome.override {
        buildGoModule = prev.buildGoModule.override { go = patchedGo; };
      };
    })
  ];

  # CVE-2026-111497: replace shared Brotli without rebuilding curl's dependents.
  # Remove once nixpkgs supplies Brotli 1.2.1 or newer. Bundled/static copies
  # need their own updates.
  system.replaceDependencies.replacements = map (brotli: {
    oldDependency = lib.getLib brotli;
    newDependency = lib.getLib (brotli.overrideAttrs (_: {
      version = "1.2.1";
      src = pkgs.fetchFromGitHub {
        owner = "google";
        repo = "brotli";
        tag = "v1.2.1";
        hash = "sha256-llY72cYffDv0ugsH0p89xIPEbElV4L8u7U/Fe8hT3gI=";
      };
    }));
  }) (lib.filter (brotli: lib.versionOlder brotli.version "1.2.1")
    ([ pkgs.brotli ] ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64
      [ pkgs.pkgsi686Linux.brotli ]));
}
