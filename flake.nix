{
  description = "Collection of my NixOS machines";

  inputs = {
    nixpkgs2205.url = "github:NixOS/nixpkgs/nixos-22.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";

    # Use vital-modules, with the same nixpkgs
    vital-modules.url = "github:nixvital/vital-modules";
    vital-modules.inputs.nixpkgs.follows = "nixpkgs";

    # Use nixos-home, with the same nixpkgs
    nixos-home.url = "github:breakds/nixos-home";
    nixos-home.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, vital-modules, nixos-home, ... }@inputs: {
    nixosConfigurations = {

      # The router welderhelper is an Intel NUC with Intel i5-4250U
      # dual cores.
      welderhelper = inputs.nixpkgs2205.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          vital-modules.nixosModules.foundation
          nixos-home.nixosModules.breakds-home
          ./machines/welderhelper
        ];
      };

      # The router pyrechomper is a topton mini PC with Intel N5105
      # quad cores.
      pyrechomper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          vital-modules.nixosModules.foundation
          nixos-home.nixosModules.breakds-home
          ./machines/pyrechomper
        ];
      };
    };
  };
}
