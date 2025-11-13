{
  description = "A simple NixOS flake";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    fakwin.url = "github:DMaroo/fakwin";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    nix-index-database.url = "github:nix-community/nix-index-database";
    plover-flake.url = "github:openstenoproject/plover-flake";
    sops-nix.url = "github:Mic92/sops-nix";

    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fakwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      nixpkgs,
      nix-index-database,
      fakwin,
      ...
    }:
    let
      unstableOverlay =
        { ... }:
        {
          nixpkgs.overlays = [
            (final: prev: {
              unstable = import inputs.nixpkgs-unstable {
                system = final.system;
                config.allowUnfree = true;
              };
              ai-tools = inputs.nix-ai-tools.packages.${final.system};
            })
          ];
        };

      commonNixModules = with inputs; [
        unstableOverlay
        fakwin.nixosModules.default
        home-manager.nixosModules.home-manager
        sops-nix.nixosModules.sops
      ];
    in
    {
      # Please replace my-nixos with your hostname
      nixosConfigurations.Kaidong-Main-Desktop = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
        };
        modules = commonNixModules ++ [
          ./home/home.nix
          ./hosts/kaidong-main-desktop/configuration.nix
          ./modules/all.nix
        ];
      };

      nixosConfigurations.Kaidong-MBP14 = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
        };
        modules = commonNixModules ++ [
          nix-index-database.nixosModules.nix-index

          ./home/home.nix
          ./hosts/kaidong-mbp14/configuration.nix
          ./modules/all.nix
        ];
      };

      # Virtualization module tests
      checks.x86_64-linux = {
        virtualization-tests = import ./tests/run-tests.nix {
          inherit inputs;
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        };
      };
    };
}
