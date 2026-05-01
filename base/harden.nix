{ config, lib, pkgs, ... }:

{
  boot.kernelPackages = lib.mkOverride 1100 pkgs.linuxPackages_latest;
}
