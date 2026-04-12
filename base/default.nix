# This is the base for all machines that is managed and serviced by
# Break and Cassandra.

{ config, lib, pkgs, ... }:

{
  time.timeZone = lib.mkDefault "America/Los_Angeles";

  # Enable to use non-free packages such as nvidia drivers
  nixpkgs.config.allowUnfree = true;

  # Boot loader
  boot = {
    loader.systemd-boot.enable = lib.mkDefault true;
    loader.efi.canTouchEfiVariables = lib.mkDefault true;
  };

  # OpenSSH is the primary management path. Tailscale also depends on it
  # being enabled for remote access over the tailnet.
  services.openssh.enable = true;

  # Drop udisks2 from the default closure; no interactive mount needs.
  services.udisks2.enable = lib.mkDefault false;

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 120d";
    };
  };

  users.extraUsers = {
    "breakds" = {
      shell = lib.mkDefault pkgs.zsh;
      useDefaultShell = false;
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      theme = "ys";
      plugins = [ "pass" "dotenv" "extract" "z" ];
    };

    shellAliases = {
      ga = "git add";
      gc = "git commit";
      gst = "git status";
    };

    interactiveShellInit = ''
      export VISUAL='emacs'
      export EDITOR='emacs'

      # Only accept autosuggestions with end-of-line, not right arrow.
      ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(end-of-line)
    '';
  };

  environment.systemPackages = with pkgs; [
    gparted pass samba emacs
    feh
    jq
    google-chrome
    scrot
    emacs
    git

    # Modern CLI utilities
    xh fd ripgrep silver-searcher bat
    lsd duf du-dust btop
  ];

  # Graphical Desktop
  services.xserver = {
    enable = true;

    xkb = {
      layout = "us";
    };

    desktopManager.gnome.enable = true;
    displayManager.gdm = {
      enable = true;
      # When using gdm, do not automatically suspend since we want to
      # keep the server running.
      autoSuspend = false;
    };
  };

  # Exclude some of the gnome3 packages
  environment.gnome.excludePackages = with pkgs.gnome3; [
    epiphany
    gnome-software
    gnome-characters
  ];
}
