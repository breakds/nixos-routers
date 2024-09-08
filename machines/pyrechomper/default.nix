{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./router.nix
    ../../base
    ../../base/tailscale.nix
  ];

  config = {
    boot.loader.efi.efiSysMountPoint = "/boot/efi";

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };

    vital.mainUser = "breakds";

    users.users."breakds" = {
      openssh.authorizedKeys.keyFiles = [
        ../../data/keys/breakds_samaritan.pub
      ];
    };

    programs.zsh.enable = true;

    networking = {
      hostName = "pyrechomper";
      hostId = "c607c8de";
    };

    # Sound
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # A container for VPN and other stuff
    containers.limbius = {
      autoStart = true;
      privateNetwork = true;
      # Steal host's physical interface ETH3 (enp4s0).
      interfaces = [ "enp4s0" ];
      enableTun = true;

      config = { config, pkgs, ... }: {
        networking.interfaces.enp4s0.useDHCP = true;

        users.users.breakds = {
          isNormalUser = true;
          home = "/home/breakds";
          extraGroups = [ "wheel" ];
          createHome = true;
          openssh.authorizedKeys.keyFiles = [
            ../../data/keys/breakds_samaritan.pub
          ];
        };

        services.openssh = {
          enable = true;
          permitRootLogin = "no";
          passwordAuthentication = false;
        };

        environment.systemPackages = with pkgs; [
          emacs git pass openconnect tmux
        ];

        # Allow sudo without password
        security.sudo.extraRules = [
          {
            users = [ "breakds" ];
            commands = [ { command = "ALL"; options = [ "NOPASSWD" ];} ];
          }
        ];

        system.stateVersion = "22.11";
      };
    };

    # Router specific

    # Use the XanMod Linux Kernel. It is a set of patches reducing latency and
    # improving performance.
    # https://dataswamp.org/~solene/2022-08-03-nixos-with-live-usb-router.html#_Kernel_and_system
    boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;

    # The service irqbalance is useful as it assigns certain IRQ calls to
    # specific CPUs instead of letting the first CPU core to handle everything.
    # This is supposed to increase performance by hitting CPU cache more often.
    services.irqbalance.enable = true;

    # This value determines the NixOS release from which the default settings
    # for stateful data, like file locations and database versions on your
    # system were taken. It‘s perfectly fine and recommended to leave this value
    # at the release version of the first install of this system. Before
    # changing this value read the documentation for this option (e.g. man
    # configuration.nix or on https://nixos.org/nixos/options.html).
    system.stateVersion = "22.11"; # Did you read the comment?
    home-manager.users."breakds".home.stateVersion = "22.11";
  };
}
