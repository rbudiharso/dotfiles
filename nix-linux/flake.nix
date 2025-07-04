{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-flatpak,
      home-manager,
      nixgl,
      ...
    }:
    let
      system = "x86_64-linux";
      username = "rb";
    in
    {
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nixgl.overlay ];
          config.allowUnfree = true;
        };
        extraSpecialArgs = {
          nixgl = nixgl;
        };
        modules = [
          nix-flatpak.homeManagerModules.nix-flatpak
          ./home.nix
        ];
      };
    };
}
