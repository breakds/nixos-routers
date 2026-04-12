{
  description = "Collection of my NixOS machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    # TODO(breakds): Get rid of breakds-home
    # Use nixos-home, with the same nixpkgs
    nixos-home.url = "github:breakds/nixos-home";
    nixos-home.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-home, ... }@inputs: {
    nixosConfigurations = {
      # The router pyrechomper is a topton mini PC with Intel N5105
      # quad cores.
      pyrechomper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-home.nixosModules.breakds-home
          ./machines/pyrechomper
        ];
      };
    };
  };
}
