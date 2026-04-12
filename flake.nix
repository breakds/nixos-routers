{
  description = "Collection of my NixOS machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      # The router pyrechomper is a topton mini PC with Intel N5105
      # quad cores.
      pyrechomper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./machines/pyrechomper
        ];
      };
    };
  };
}
