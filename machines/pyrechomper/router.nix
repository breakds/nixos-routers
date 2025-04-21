{ config, lib, pkgs, ... }:

# TODO(breakds)
# 1. Add mitmproxy
# 2. networkd
# 3. Use nftables
# 4. Filter out martian packets using kernel option rp_filter (https://github.com/ghostbuster91/blogposts/blob/a2374f0039f8cdf4faddeaaa0347661ffc2ec7cf/router2023-part2/main.md)

let nics = rec {
      uplink = "enp2s0";
      local = "enp3s0";
    };

    vlanIds = {
      home = 90;
      guest = 100;
      iot = 104;
    };

    vlans = {
      home = "home${toString vlanIds.home}";
      guest = "guest${toString vlanIds.guest}";
      iot = "iot${toString vlanIds.iot}";
    };

    ips = {
      limbius = "10.77.1.193";
      octavian-10g = "10.77.1.131";
      radahn = "10.77.1.35";  # The upper ethernet port
      forgery = "10.77.1.136";
    };

in {
  # Enable IPv6 as we want to support both IPv4 and IPv6.
  networking.enableIPv6 = true;

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
    "2606:4700:4700::1001"  # Cloudflare IPv6 one.zero.zero.one
  ];

  # Enable Kernel IP Forwarding (i.e. routing).
  #
  # For more details, refer to
  # https://unix.stackexchange.com/questions/14056/what-is-kernel-ip-forwarding
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv4.conf.default.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
    "net.ipv6.conf.default.forwarding" = true;
  };

  services.unbound = {
    enable = true;
    # I think this is important because I may accidently break the unbound
    # server during debugging or testing new configuration, and this keeps the
    # router's DNS queries being answered even when unbound is down.
    resolveLocalQueries = false;
    settings = {
      server = {
        interface = [ "127.0.0.1" "10.77.1.1" ];
        access-control =  [
          "0.0.0.0/0 refuse"
          "127.0.0.0/8 allow"
          "10.77.1.0/24 allow"
        ];
	      prefetch = "yes";
      };

      # https://gist.github.com/BigSully/a36cb8763eb7832a6c1f7d25fc174c09
      forward-zone = [
        {
          name = ".";
          forward-tls-upstream = "yes";

          forward-addr = [
            # Google
  	        "8.8.8.8@853#dns.google"
            "8.8.4.4@853#dns.google"
            "2001:4860:4860::8888@853#dns.google"
            "2001:4860:4860::8844@853#dns.google"

            # Cloudflare
            "1.1.1.1@853#cloudflare-dns.com"
            "1.0.0.1@853#cloudflare-dns.com"
            "2606:4700:4700::1111@853#cloudflare-dns.com"
            "2606:4700:4700::1001@853#cloudflare-dns.com"

            # Quad9 ( Slowest, only serve as backup when the faster are
	          # temporarily down. )
            "149.112.112.112@853#dns.quad9.net"
            "9.9.9.10@853#dns.quad9.net"
            "2620:fe::fe@853#dns.quad9.net"
            "2620:fe::9@853#dns.quad9.net"
	        ];
        }
      ];
    };
  };

  # Open port 53 for downlink DNS request
  networking.firewall.interfaces."${vlans.home}" = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };

  # https://kea.readthedocs.io/en/kea-2.4.1/arm/dhcp4-srv.html
  services.kea.dhcp4 = {
    enable = true;

    settings = {
      # A 7-day valid lifetime before a device need to to be renewed. Having
      # such a long valid lifetime because the devices are mostly connected and
      # stays in connection for long.
      valid-lifetime = 604800;
      renew-timer = 302400;   # 50.0% of the valid-lifetime.
      rebind-timer = 529200;  # 87.5% of the valid-lifetime.

      # The interfaces to be used by the server.
      interfaces-config = {
        interfaces = [ vlans.home vlans.guest vlans.iot ];
      };

      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };

      # For the option data, the valid options can be found here:
      # https://kea.readthedocs.io/en/kea-2.4.1/arm/dhcp4-srv.html#dhcp4-std-options-list
      subnet4 = [
        {
          subnet = "10.77.1.0/24";
          interface = vlans.home;
          pools = [ { pool = "10.77.1.20 - 10.77.1.240"; } ];
          option-data = [
            { name = "routers"; data = "10.77.1.1"; }
            { name = "domain-name-servers"; data = "10.77.1.1"; }
            { name = "broadcast-address"; data = "10.77.1.255"; }
            { name = "subnet-mask"; data = "255.255.255.0"; }
          ];
          reservations = [
            { hw-address = "7C:10:C9:3C:52:B9";
              ip-address = "10.77.1.117";
              hostname = "gilgamesh"; }

            { hw-address = "b4:96:91:9f:f9:f8";  # enp4s0f0 (Intel X550-T2, Upper)
              ip-address = ips.octavian-10g;
              hostname = "octavian"; }

            { hw-address = "FC:34:97:A5:CF:55";  # The lower port
              ip-address = "10.77.1.128";
              hostname = "lorian"; }

            { hw-address = "58:11:22:d7:21:64";  # The upper port
              ip-address = ips.radahn;
              hostname = "radahn"; }

            { hw-address = "04:cf:4b:21:68:6c"; # wifi
              ip-address = "10.77.1.187";
              hostname = "hand"; }

            { hw-address = "a0:36:bc:bb:4f:8e";
              ip-address = "10.77.1.185";
              hostname = "malenia"; }

            {
              hw-address = "7c:2b:e1:13:8c:8d";  # ETH3 of this router (enp4s0)
              ip-address = ips.limbius;
              hostname = "limbius"; }

            {
              hw-address = "1c:69:7a:03:9c:1a";
              ip-address = ips.forgery;
              hostname = "forgery"; }
          ];
        }

        {
          subnet = "10.77.100.0/24";
          interface = vlans.guest;
          pools = [ { pool = "10.77.100.20 - 10.77.100.240"; } ];
          option-data = [
            { name = "routers"; data = "10.77.100.1"; }
            { name = "domain-name-servers"; data = "1.1.1.1, 8.8.8.8, 8.8.4.4"; }
            { name = "broadcast-address"; data = "10.77.100.255"; }
            { name = "subnet-mask"; data = "255.255.255.0"; }
          ];
        }

        {
          # A lot more IPs to the IoT subnet and therefore the netmask is only 22
          # bits instead of the normal 24 bits.
          subnet = "10.77.104.0/22";
          interface = vlans.iot;
          pools = [ { pool = "10.77.104.20 - 10.77.107.240"; } ];
          option-data = [
            { name = "routers"; data = "10.77.104.1"; }
            { name = "domain-name-servers"; data = "1.1.1.1, 8.8.8.8, 8.8.4.4"; }
            { name = "broadcast-address"; data = "10.77.107.255"; }
            { name = "subnet-mask"; data = "255.255.252.0"; }
          ];
        }
      ];
    };
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
      ip6tables -A FORWARD -i lo -j ACCEPT
      ip6tables -A FORWARD -o lo -j ACCEPT
      ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    '';
    # TODO(breakds): Keep IoT devices from being able to access the
    # main network unless specifically allowed.
  };

  # NAT
  networking.nat = {
    enable = true;
    enableIPv6 = false;
    externalInterface = nics.uplink;
    internalInterfaces = [ vlans.home vlans.guest vlans.iot ];
    internalIPs = [ "10.77.1.0/24" "10.77.100.0/24" "10.77.104.0/22" ];
    forwardPorts = [
      { sourcePort = 22; destination = "${ips.octavian-10g}:22"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 80; destination = "${ips.octavian-10g}:80"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 443; destination = "${ips.octavian-10g}:443"; loopbackIPs = [ "23.119.127.221" ]; }
    ];
  };

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

  networking.interfaces."${vlans.iot}" = {
    # This is going to be the router's IP to internal devices connects
    # to it.
    ipv4.addresses = [ {
      address = "10.77.104.1";
      prefixLength = 22;  # Subnet Mask = 255.255.252.0
    } ];
    useDHCP = false;
  };

  # +------------------+
  # | Applications     |
  # +------------------+

  # iperf3 Server for speed/bandwidth testing
  services.iperf3 = {
    # NOTE(breakds): Open this when testing is needed.
    enable = false;
    openFirewall = false;
  };

  # Other helpful tools
  environment.systemPackages = with pkgs; [
    tcpdump ethtool
  ];

  # Avahi for local Multicast DNS
  services.avahi = {
    enable = true;
    reflector = true;
    allowInterfaces = [
      vlans.home
      vlans.iot
    ];
  };
}
