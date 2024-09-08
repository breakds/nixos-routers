# This is the base for all machines that is managed and serviced by
# Break and Cassandra.

{ config, lib, pkgs, ... }:

{
  time.timeZone = lib.mkDefault "America/Los_Angeles";

  # Enable to use non-free packages such as nvidia drivers
  nixpkgs.config.allowUnfree = true;

  users.extraUsers = {
    "breakds" = {
      shell = lib.mkDefault pkgs.zsh;
      useDefaultShell = false;
    };
  };

  vital.programs.modern-utils.enable = true;

  environment.systemPackages = with pkgs; [
    gparted pass samba emacs
  ] ++ lib.optionals config.vital.graphical.enable [
    feh
    jq
    google-chrome
    scrot
    emacs
    git
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
