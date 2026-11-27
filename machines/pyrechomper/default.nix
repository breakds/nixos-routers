{
  imports = [
    ./hardware-configuration.nix
    ./router.nix
    ./power-cycle.nix
    ../../base
    ../../base/tailscale.nix
    ../../base/harden.nix
  ];

  config = {
    services.openssh.hostKeys = [
      { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
    ];
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

    users.users.breakds = {
      isNormalUser = true;
      uid = 1000;
      home = "/home/breakds";
      description = "breakds";
      extraGroups = [ "wheel" "dialout" "uucp" ];
      openssh.authorizedKeys.keyFiles = [
        ../../data/keys/breakds_malenia.pub
      ];
    };

    users.groups.breakds.gid = 1000;

    networking = {
      hostName = "pyrechomper";
      hostId = "c607c8de";
    };

    # Allow remote deployments to copy locally built, unsigned store paths.
    nix.settings.trusted-users = [ "breakds" ];

    # Sound (pipewire)
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Router specific

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
  };
}
