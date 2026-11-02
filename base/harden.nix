{ config, lib, pkgs, ... }:

{
  boot.kernelPackages = lib.mkOverride 1100 pkgs.linuxPackages_latest;

  assertions = [{
    assertion = lib.versionAtLeast config.boot.kernelPackages.kernel.version "7.3";
    message = "The router requires Linux 7.3 or newer for CVE-2026-98432.";
  }];
}
