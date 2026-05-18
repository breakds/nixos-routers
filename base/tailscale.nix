{ config, lib, pkgs, ... }:

{
  config = {
    services.tailscale = {
      enable = true;
      port = 41661;  # The default is 41641.
      useRoutingFeatures = "server";
    };

    networking.firewall = {
      allowedUDPPorts = [ config.services.tailscale.port ];
    };

    environment.systemPackages = with pkgs; [ tailscale ];
  };
}
