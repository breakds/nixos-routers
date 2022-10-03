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

  environment.systemPackages = with pkgs; [
    gparted pass samba emacs
  ] ++ lib.optionals config.vital.graphical.enable [
    feh
    jq
    google-chrome
    scrot
  ];
}
