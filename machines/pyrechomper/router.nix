{ config, lib, pkgs, ... }:

let nics = rec {
      uplink = "enp2s0";
      local = "enp3s0";
    };

    vlanIds = {
      home = 90;
      guest = 100;
      iot = 105;
    };

    vlans = {
      home = "home${toString vlanIds.home}";
      guest = "guest${toString vlanIds.guest}";
      iot = "iot${toString vlanIds.iot}";
    };

in {
  # Create 2 separate VLAN devices for the localNIC.
  networking.vlans = {
    "${vlans.home}" = {
      id = vlanIds.home;
      interface = nics.local;
    };

    "${vlans.guest}" = {
      id = vlanIds.guest;
      interface = nics.local;
    };

    "${vlans.iot}" = {
      id = vlanIds.iot;
      interface = nics.local;
    };
  };
  
  networking.networkmanager.enable = lib.mkForce false;
  networking.nameservers = [
    "8.8.8.8"  # Google
    "1.1.1.1"  # Cloudflare
    "2606:4700:4700::1111"  # Cloudflare IPv6 one.one.one.one
    "2606:4700:4700::1001"  # Cloudflare IPv6 one.one.one.one
  ];

  networking.enableIPv6 = true;

  # Enable Kernel IP Forwarding.
  #
  # For more details, refer to
  # https://unix.stackexchange.com/questions/14056/what-is-kernel-ip-forwarding
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv4.conf.default.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
    "net.ipv6.conf.default.forwarding" = true;
  };

  # Enable DHCP
  services.dhcpd4 = {
    enable = true;
    interfaces = [ vlans.home vlans.guest ];
    machines = [
      {
        ethernetAddress = "7C:10:C9:3C:52:B9";
        hostName = "gilgamesh";
        ipAddress = "10.77.1.117";
      }
      {
        ethernetAddress = "24:b6:fd:f6:25:a4"; # iDrac of richelieu
        hostName = "idracJHVPDV1";
        ipAddress = "10.77.1.120";
      }
      {
        ethernetAddress = "d4:ae:52:98:bc:3c"; # Note that this is the 1st nic
        hostName = "richelieu";
        ipAddress = "10.77.1.121";
      }
      {
        ethernetAddress = "fc:34:97:68:ef:35"; # eno1
        hostName = "octavian";
        ipAddress = "10.77.1.130";
      }
      {
        ethernetAddress = "FC:34:97:A5:CB:C2";  # Ethernet Port 0, the lower one
        hostName = "lothric";
        ipAddress = "10.77.1.127";
      }
      {
        ethernetAddress = "FC:34:97:A5:CF:55";  # Ethernet Port 0, the lower one
        hostName = "lorian";
        ipAddress = "10.77.1.128";
      }
      {
        ethernetAddress = "DC:71:96:98:95:EF";  # The WiFi
        hostName = "zero";
        ipAddress = "10.77.1.221";
      }
      {
        # WiFi
        ethernetAddress = "04:cf:4b:21:68:6c";
        hostName = "hand";
        ipAddress = "10.77.1.187";
      }
      {
        ethernetAddress = "a0:36:bc:bb:4f:8e";
        hostName = "malenia";
        ipAddress = "10.77.1.185";
      }
      {
        ethernetAddress = "dc:a6:32:8d:66:dd";
        hostName = "armlet";
        ipAddress = "10.77.1.188";
      }
    ];
    
    extraConfig = ''
      option domain-name-servers 1.1.1.1, 8.8.8.8, 8.8.4.4;
      option subnet-mask 255.255.255.0;

      default-lease-time 25920000;
      max-lease-time 25920000;

      subnet 10.77.1.0 netmask 255.255.255.0 {
        interface ${vlans.home};
        range 10.77.1.20 10.77.1.240;
        option routers 10.77.1.1;
        option broadcast-address 10.77.1.255;
      }
      subnet 10.77.100.0 netmask 255.255.255.0 {
        interface ${vlans.guest};
        range 10.77.100.20 10.77.100.240;
        option routers 10.77.100.1;
        option broadcast-address 10.77.100.255;
      }
    '';
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowPing = true;
    logRefusedConnections = false;
    # If rejectPackets = true, refused packets are rejected rather than dropped (ignored). This
    # means that an ICMP "port unreachable" error message is sent back to the client (or a TCP RST
    # packet in case of an existing connection). Rejecting packets makes port scanning somewhat
    # easier.
    rejectPackets = false;
    # Traffic coming in from these interfaces will be accepted unconditionally. Traffic from the
    # loopback (lo) interface will always be accepted.
    trustedInterfaces = [ vlans.home ];
    # Do not perform reverse path filter test on a packet.
    checkReversePath = false;

    # The following is about preventing the outside packet from accessing
    # internal servers via IPv6. This is done by asking the router to stop
    # forwarding packets unless they are going outside or coming back w.t.r. an
    # already established connection.
    extraCommands = ''
      ip6tables -P FORWARD DROP
      ip6tables -A FORWARD -i ${vlans.home} -o ${nics.uplink} -j ACCEPT
      ip6tables -A FORWARD -i ${vlans.guest} -o ${nics.uplink} -j ACCEPT
      ip6tables -A FORWARD -i lo -j ACCEPT
      ip6tables -A FORWARD -o lo -j ACCEPT
      ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    '';
  };

  # NAT
  networking.nat = {
    enable = true;
    enableIPv6 = false;
    externalInterface = nics.uplink;
    internalInterfaces = [ vlans.home ];
    internalIPs = [ "10.77.1.0/24" ];
    forwardPorts = [
      { sourcePort = 22; destination = "10.77.1.130:22"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 80; destination = "10.77.1.130:80"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 443; destination = "10.77.1.130:443"; loopbackIPs = [ "23.119.127.221" ]; }
    ];
  };

  # Topology for the managed switch:
  #
  #
  #
  #  +-----+-----+-----+
  #  |  A  |  B  |  C  | <- managed switch
  #  |     |     |     |
  #  +--|--+--|--+--|--+
  #     |     |     +------------------ Wifi AP/Devices
  #     |     |
  #     |     +------------ Modem
  #   router
  #
  # If the vlan ID for wan is 60, and the vlan ID for lan is 90, we
  # need to configure
  #
  # 1. A as a Trunk Port that allows 60 and 90
  # 2. B as an Access (Untagged) Port with Vlan ID (and PVID) = 60
  # 3. C as an Access (Untagged) Port with Vlan ID (and PVID) = 90
  # networking.interfaces."${cfg.nic}".useDHCP = false;

  # Let the modem "DHCP me" for the uplink VLAN. The modem is set to
  # IP Passthrough mode (for ATT, it is DHCPS-fixed more
  # specifically). This will pass the modem's public IP to the Uplink
  # (WAN) interface.
  networking.interfaces."${nics.uplink}".useDHCP = true;
  # Now we need to make more specific configuration to the DHCP client
  # than handles the Uplink (WAN) interface because of IPv6. Credit to
  # KJ and Francis Begyn
  # (https://francis.begyn.be/blog/ipv6-nixos-router).
  #
  # The main purpose here is to assign a IPv6 prefix delegation to the
  # LAN interface(s), so that together with a router advertisement
  # service it can provide automatic IPv6 address configuration for
  # the internal network.

  networking.dhcpcd = {
    enable = true;

    # Do not de-configure the interface and configurations when it
    # exists. I probably do not need persistent based on my
    # understanding, but I'll just keep it on.
    persistent = true;
    allowInterfaces = [ nics.uplink ];

    extraConfig = ''
      # Don't touch our DNS settings
      nohook resolv.conf

      # Generate a RFC 4361 complient DHCP ID. This unique identifier
      # plus the IAID (see below) will be used as client ID.
      duid

      # The hardware address (i.e. MAC) address will be disguised by a
      # generated RFC7217 address, so that the actual MAC is not exposed
      # to the internet.
      slaac private

      # Do not solicit or accept IPv6 Router Advertisement.
      noipv6rs

      interface ${nics.uplink}
        # Enable routing solicitation for Uplink (WAN)
        ipv6rs
        # Request an IPv6 address for iaid 1
        ia_na 1
        # Request an IPv6 Prefix Delegation (PD) for iaid 2
        # The prefix length should be 56
        # The PD is assigned to LAN, with prefix length = 64
        # The suffix is set to 77 (Hex 4D)
        # An example IPv6 PD to LAN will look like
        # 3600:9200:7f7f:a66f::4d/64
        ia_pd 2//56 ${vlans.home}/0/64/77
        # Request an IPv6 Prefix Delegation (PD) for iaid 100
        ia_pd 100//56 ${vlans.guest}/0/64/77
    '';
  };

  services.corerad = {
    enable = true;
    settings = {
      debug = {
        address = "localhost:9430";
        prometheus = true;              # enable prometheus metrics
      };
      interfaces = [
        {
          name = nics.uplink;
          monitor = false;              # see the remark below
        }
        {
          name = vlans.home;
          advertise = true;
          prefix = [
            { prefix = "::/64"; }
          ];
        }
        {
          name = vlans.guest;
          advertise = true;
          prefix = [
            { prefix = "::/64"; }
          ];
        }
      ];
    };
  };

  networking.interfaces."${vlans.home}" = {
    # This is going to be the router's IP to internal devices connects
    # to it.
    ipv4.addresses = [ {
      address = "10.77.1.1";
      prefixLength = 24;  # Subnet Mask = 255.255.255.0
    } ];
    useDHCP = false;
  };

  networking.interfaces."${vlans.guest}" = {
    # This is going to be the router's IP to internal devices connects
    # to it.
    ipv4.addresses = [ {
      address = "10.77.100.1";
      prefixLength = 24;  # Subnet Mask = 255.255.255.0
    } ];
    useDHCP = false;
  };

  # +------------------+
  # | Applications     |
  # +------------------+

  # iperf3 Server for speed/bandwidth testing
  services.iperf3 = {
    enable = true;
    openFirewall = true;
  };

  # Other helpful tools
  environment.systemPackages = with pkgs; [
    tcpdump ethtool
  ];

  # Avahi for local Multicast DNS
  services.avahi = {
    enable = true;
    reflector = true;
    interfaces = [
      vlans.home
    ];
  };
}
