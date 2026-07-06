{ config, lib, pkgs, ... }:

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

    # RFC 4193 ULA prefix for routable local IPv6 across VLANs.
    # Matter needs IPv6 beyond link-local when controllers and devices
    # live on different L3 segments.
    ulaPrefix = "fd85:6432:2320";

    ips = {
      limbius = "10.77.1.193";
      octavian-10g = "10.77.1.131";
      radahn = "10.77.1.35";  # The upper ethernet port
      forgery = "10.77.1.136";
      cradle = "10.77.1.56";
      brock = "10.77.1.45"; # The bottom-right port
      shelly-garage-door = "10.77.1.63";  # The Shelly 1 Gen 4 on Garage Door (deprecated)
      solar-pi = "10.77.1.52";
      shelly-office-light = "10.77.1.44";
      aqara-g5-porch = "10.77.104.27";
      aqara-g5-deck = "10.77.104.29";
      ratgdo = "10.77.104.38";
      gree-ac-1 = "10.77.104.32";
      gree-ac-2 = "10.77.104.34";
      gree-ac-3 = "10.77.104.37";
      gree-ac-4 = "10.77.104.35";
    };

    # Script that reads Kea DHCP leases and adds PTR records to
    # unbound so that AdGuard Home can resolve client IPs to hostnames.
    keaUnboundSync = pkgs.writeShellScript "kea-unbound-sync" ''
      set -euo pipefail

      LEASE_FILE="/var/lib/kea/dhcp4.leases.2"
      [ ! -s "$LEASE_FILE" ] && LEASE_FILE="/var/lib/kea/dhcp4.leases"
      [ ! -s "$LEASE_FILE" ] && exit 0

      NOW=$(${pkgs.coreutils}/bin/date +%s)

      ${pkgs.coreutils}/bin/tail -n +2 "$LEASE_FILE" | while IFS=',' read -r ip _ _ _ expire _ _ _ hostname _; do
        [ -z "$hostname" ] && continue
        [ "$expire" -lt "$NOW" ] 2>/dev/null && continue

        # Strip trailing dots (e.g. "gilgamesh." → "gilgamesh").
        hostname="''${hostname%.}"

        # Convert e.g. 10.77.1.35 to 35.1.77.10.in-addr.arpa.
        IFS='.' read -r a b c d <<< "$ip"
        ${pkgs.unbound}/bin/unbound-control local_data "''${d}.''${c}.''${b}.''${a}.in-addr.arpa. 3600 IN PTR ''${hostname}." || true
      done
    '';

in {
  # Enable IPv6 as we want to support both IPv4 and IPv6.
  networking.enableIPv6 = true;

  # Use systemd-networkd for declarative network configuration.
  # Disable systemd-resolved since unbound + AdGuard Home handle DNS.
  networking.useNetworkd = true;
  networking.useDHCP = false;
  # resolved manages /etc/resolv.conf for the router's own DNS, but
  # we disable its stub listener so it doesn't conflict with AdGuard
  # Home on port 53.
  services.resolved = {
    enable = true;
    extraConfig = "DNSStubListener=no";
  };
  # Boot is considered online as soon as any one interface is up.
  # Without this, unused ports with no cable block boot for 2 minutes.
  systemd.network.wait-online.anyInterface = true;

  # VLAN devices on the trunk port (enp3s0).
  systemd.network.netdevs = {
    "10-${vlans.home}" = {
      netdevConfig = { Kind = "vlan"; Name = vlans.home; };
      vlanConfig.Id = vlanIds.home;
    };
    "10-${vlans.guest}" = {
      netdevConfig = { Kind = "vlan"; Name = vlans.guest; };
      vlanConfig.Id = vlanIds.guest;
    };
    "10-${vlans.iot}" = {
      netdevConfig = { Kind = "vlan"; Name = vlans.iot; };
      vlanConfig.Id = vlanIds.iot;
    };
  };

  systemd.network.networks = {
    # Trunk port: carries all VLAN traffic, no IP of its own.
    "20-${nics.local}" = {
      matchConfig.Name = nics.local;
      vlan = [ vlans.home vlans.guest vlans.iot ];
      networkConfig.LinkLocalAddressing = "no";
    };

    # Uplink (WAN): gets public IPv4 via DHCP from the ATT modem
    # (IP Passthrough / DHCPS-fixed mode) and IPv6 address + Prefix
    # Delegation via DHCPv6. The delegated prefix is carved into /64
    # subnets and assigned to downstream VLANs.
    "20-${nics.uplink}" = {
      matchConfig.Name = nics.uplink;
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
        # Use a privacy address (RFC 7217) so the real MAC is not
        # exposed to the internet.
        IPv6PrivacyExtensions = true;
      };
      # Don't let the ISP's DHCP override our DNS settings.
      dhcpV4Config.UseDNS = false;
      dhcpV6Config = {
        UseDNS = false;
        # Request a /56 prefix block from ATT for internal networks.
        PrefixDelegationHint = "::/56";
      };
      ipv6AcceptRAConfig.UseDNS = false;
    };

    # Home VLAN: trusted devices. Gets a /64 carved from the
    # delegated prefix so devices can auto-configure IPv6 addresses.
    "30-${vlans.home}" = {
      matchConfig.Name = vlans.home;
      address = [
        "10.77.1.1/24"
        "${ulaPrefix}:1::1/64"
      ];
      networkConfig = {
        DHCPPrefixDelegation = true;
        IPv6AcceptRA = false;
      };
      # Assign the first /64 subnet from the delegated prefix.
      # Token = "::4d" sets the router's IPv6 address suffix to 0x4d
      # (77 in decimal), matching the old dhcpcd configuration.
      dhcpPrefixDelegationConfig = {
        UplinkInterface = nics.uplink;
        SubnetId = "0";
        Token = "::4d";
      };
    };

    # Guest VLAN: internet only, no access to other VLANs.
    "30-${vlans.guest}" = {
      matchConfig.Name = vlans.guest;
      address = [ "10.77.100.1/24" ];
      networkConfig.IPv6AcceptRA = false;
    };

    # IoT VLAN: limited access, /22 for more address space.
    "30-${vlans.iot}" = {
      matchConfig.Name = vlans.iot;
      address = [
        "10.77.104.1/22"
        "${ulaPrefix}:104::1/64"
      ];
      networkConfig.IPv6AcceptRA = false;
    };

    # Unused NIC (enp5s0): no cable, don't try DHCP, don't block boot.
    "90-enp5s0" = {
      matchConfig.Name = "enp5s0";
      networkConfig = {
        DHCP = "no";
        LinkLocalAddressing = "no";
      };
      linkConfig.RequiredForOnline = "no";
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

    # Log packets with impossible source addresses for debugging.
    "net.ipv4.conf.all.log_martians" = true;
    "net.ipv4.conf.default.log_martians" = true;

    # Grant unbound the 4 MB socket buffers it requests.
    "net.core.wmem_max" = 4194304;
    "net.core.rmem_max" = 4194304;
  };

  services.unbound = {
    enable = true;
    # Keep the router's own DNS independent of unbound so that a
    # broken unbound config doesn't lock us out.
    resolveLocalQueries = false;
    # Enable the control socket so unbound-control can add PTR records
    # at runtime (used by kea-unbound-sync).
    localControlSocketPath = "/run/unbound/unbound.ctl";
    settings = {
      server = {
        # Unbound now only serves AdGuard Home on localhost.
        interface = [ "127.0.0.1" ];
        port = 5335;
        access-control =  [
          "0.0.0.0/0 refuse"
          "127.0.0.0/8 allow"
        ];
	      prefetch = "yes";

        # Serve reverse DNS for private subnets so AdGuard Home can
        # resolve client IPs to hostnames via rDNS.  "transparent"
        # means: answer if we have a PTR record, otherwise return
        # NXDOMAIN (no upstream would answer for RFC1918 anyway).
        local-zone = [
          "\"1.77.10.in-addr.arpa.\" transparent"
          "\"100.77.10.in-addr.arpa.\" transparent"
          "\"104.77.10.in-addr.arpa.\" transparent"
          "\"105.77.10.in-addr.arpa.\" transparent"
          "\"106.77.10.in-addr.arpa.\" transparent"
          "\"107.77.10.in-addr.arpa.\" transparent"
        ];

        local-data = [
          "\"temporal.breakds.net. 3600 IN A ${ips.octavian-10g}\""
          "\"home.breakds.net. 3600 IN A ${ips.octavian-10g}\""
        ];
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

  # AdGuard Home: DNS-level ad/tracker blocking in front of unbound.
  # Clients query AdGuard Home on port 53; non-blocked queries are
  # forwarded to unbound on localhost:5335 for recursive resolution.
  services.adguardhome = {
    enable = true;
    # Allow managing blocklists and settings via the web UI.
    mutableSettings = true;
    settings = {
      http.address = "10.77.1.1:3000";
      dns = {
        bind_hosts = [ "10.77.1.1" "10.77.104.1" ];
        port = 53;
        upstream_dns = [ "127.0.0.1:5335" ];
        bootstrap_dns = [ "8.8.8.8" "1.1.1.1" ];
      };
      clients.runtime_sources = {
        rdns = true;
        arp = true;
        hosts = true;
      };
    };
  };

  # Open port 53 (DNS) and 3000 (AdGuard Home dashboard) for home VLAN.
  networking.firewall.interfaces."${vlans.home}" = {
    allowedTCPPorts = [ 22 53 3000 ];
    allowedUDPPorts = [ 53 ];
  };

  networking.firewall.interfaces."${vlans.iot}" = {
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
        # The VLAN interfaces live on the enp3s0 trunk and their carrier
        # can come up after kea starts (network-online.target fires on the
        # WAN link first, see wait-online.anyInterface above). Without
        # retries kea gives up after one attempt, opens no sockets, and
        # stays deaf to DHCP until the next restart. Retry instead.
        service-sockets-max-retries = 20;
        service-sockets-retry-wait-time = 5000;  # ms -> ~100s of retries
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
          id = 1;
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

            {
              hw-address = "58:47:ca:70:51:ae";
              ip-address = ips.cradle;
              hostname = "cradle"; }

            {
              hw-address = "00:90:27:f7:39:76";
              ip-address = ips.brock;
              hostname = "brock"; }

            {
              hw-address = "cc:ba:97:c8:3f:68";
              ip-address = ips.shelly-garage-door;
            }

            {
              hw-address = "dc:a6:32:8d:66:e0";  # WiFi
              ip-address = ips.solar-pi;
            }

            {
              hw-address = "28:37:2f:2a:4c:60";
              ip-address = ips.shelly-office-light;
            }
          ];
        }

        {
          id = 2;
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
          id = 3;
          # A lot more IPs to the IoT subnet and therefore the netmask is only 22
          # bits instead of the normal 24 bits.
          subnet = "10.77.104.0/22";
          interface = vlans.iot;
          pools = [ { pool = "10.77.104.20 - 10.77.107.240"; } ];
          option-data = [
            { name = "routers"; data = "10.77.104.1"; }
            { name = "domain-name-servers"; data = "10.77.104.1"; }
            { name = "broadcast-address"; data = "10.77.107.255"; }
            { name = "subnet-mask"; data = "255.255.252.0"; }
          ];
          reservations = [
            {
              hw-address = "18:c2:3c:5a:9a:99";
              ip-address = ips.aqara-g5-porch;
              hostname = "aqara-g5-porch";
            }

            {
              hw-address = "18:c2:3c:5a:8f:6a";
              ip-address = ips.aqara-g5-deck;
              hostname = "aqara-g5-deck";
            }

            {
              hw-address = "68:25:dd:fb:9d:5c";
              ip-address = ips.ratgdo;
              hostname = "ratgdo";
            }

            {
              hw-address = "58:0d:0d:f6:3b:21";
              ip-address = ips.gree-ac-1;
              hostname = "gree-ac-1";
            }

            {
              hw-address = "58:0d:0d:f6:05:fa";
              ip-address = ips.gree-ac-2;
              hostname = "gree-ac-2";
            }

            {
              hw-address = "58:0d:0d:f6:34:c9";
              ip-address = ips.gree-ac-3;
              hostname = "gree-ac-3";
            }

            {
              hw-address = "58:0d:0d:fa:df:40";
              ip-address = ips.gree-ac-4;
              hostname = "gree-ac-4";
            }
          ];
        }
      ];
    };
  };

  # Use nftables as the firewall backend (unified IPv4/IPv6).
  networking.nftables.enable = true;

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
    # Drop packets with spoofed source addresses. "loose" checks that
    # some route to the source exists without requiring it to be via the
    # ingress interface, which avoids false drops on a multi-VLAN router.
    checkReversePath = "loose";

    # Prevent outside packets from accessing internal servers. The
    # router will stop forwarding packets unless they are going outside
    # or coming back as part of an already established connection.
    # Port-forwarded traffic (e.g. 22/80/443 to octavian) is also
    # allowed through automatically.
    #
    # Technically this sets the FORWARD chain policy to "drop", with
    # exceptions for conntrack established/related and DNAT traffic
    # handled by the NixOS nftables module.
    filterForward = true;

    extraForwardRules = ''
      # Allow home network to reach the internet via IPv6.
      meta nfproto ipv6 iifname "${vlans.home}" oifname "${nics.uplink}" accept

      # Allow home network to manage IoT devices (cameras, ratgdo, etc.).
      # Return traffic is handled by conntrack (established/related).
      iifname "${vlans.home}" oifname "${vlans.iot}" accept

      # Tailscale exit node: allow tailnet clients to reach the internet.
      iifname "tailscale0" oifname "${nics.uplink}" accept

      # RA Guard: block rogue Router Advertisements from crossing VLANs.
      icmpv6 type nd-router-advert drop

      # Allow approved tailnet users to reach the trusted home LAN.
      # User-level authorization is enforced by Tailscale ACLs.
      iifname "tailscale0" oifname "${vlans.home}" ip daddr 10.77.1.0/24 accept
    '';

    extraInputRules = ''
      # RA Guard: drop rogue Router Advertisements from LAN interfaces.
      # Only the router itself should send RAs. For L2 protection of
      # clients on the same VLAN, enable RA guard on the switch.
      iifname { "${vlans.home}", "${vlans.guest}", "${vlans.iot}" } icmpv6 type nd-router-advert drop
    '';

  };

  # NAT
  networking.nat = {
    enable = true;
    enableIPv6 = false;
    externalInterface = nics.uplink;
    internalInterfaces = [ vlans.home vlans.guest vlans.iot "tailscale0" ];
    internalIPs = [ "10.77.1.0/24" "10.77.100.0/24" "10.77.104.0/22" "100.64.0.0/10" ];
    forwardPorts = [
      { sourcePort = 22; destination = "${ips.octavian-10g}:22"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 80; destination = "${ips.octavian-10g}:80"; loopbackIPs = [ "23.119.127.221" ]; }
      { sourcePort = 443; destination = "${ips.octavian-10g}:443"; loopbackIPs = [ "23.119.127.221" ]; }
    ];
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
            { prefix = "${ulaPrefix}:1::/64"; }
          ];
        }
        {
          name = vlans.iot;
          advertise = true;
          prefix = [
            { prefix = "${ulaPrefix}:104::/64"; }
          ];
        }
      ];
    };
  };

  # Periodically sync Kea DHCP hostnames into unbound as PTR records
  # so that AdGuard Home's rDNS resolution shows device names.
  systemd.services.kea-unbound-sync = {
    description = "Sync Kea DHCP hostnames to unbound PTR records";
    after = [ "unbound.service" "kea-dhcp4-server.service" ];
    requires = [ "unbound.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = keaUnboundSync;
    };
  };

  systemd.timers.kea-unbound-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1h";
    };
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
    tcpdump ethtool dig
  ];

  # Avahi for local Multicast DNS
  services.avahi = {
    enable = true;
    reflector = true;
    allowInterfaces = [
      vlans.home
      vlans.iot
    ];
    openFirewall = true;
  };
}
