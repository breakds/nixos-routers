{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./router.nix
    ../../base
    ../../base/tailscale.nix
  ];
  
  config = {
    vital.mainUser = "breakds";

    users.users."breakds" = {
      openssh.authorizedKeys.keyFiles = [
        ../../data/keys/breakds_samaritan.pub
      ];
    };

    vital.graphical.enable = true;

    networking = {
      hostName = "welderhelper";
      hostId = "7f100a7e";
      
      # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
      
      # Globally disable DHCP.
      useDHCP = false;
      
      # Set DHCP individually for hardware network cards.
      interfaces.eno1.useDHCP = false;
      interfaces.wlp2s0.useDHCP = true;
    };

    # This value determines the NixOS release from which the default settings
    # for stateful data, like file locations and database versions on your
    # system were taken. It‘s perfectly fine and recommended to leave this value
    # at the release version of the first install of this system. Before
    # changing this value read the documentation for this option (e.g. man
    # configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "20.09"; # Did you read the comment?
  };
}
