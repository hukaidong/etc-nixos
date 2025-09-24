{
  description = "A simple NixOS flake";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    nix-index-database.url = "github:nix-community/nix-index-database";

    emacs-overlay.url = "github:nix-community/emacs-overlay";
    home.url = "git+file:/home/kaidong/.config/home-manager";
    plover-flake.url = "github:openstenoproject/plover-flake";

    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      nixpkgs,
      home,
      home-manager,
      sops-nix,
      nix-index-database,
      ...
    }:
    {
      # Please replace my-nixos with your hostname
      nixosConfigurations.Kaidong-Main-Desktop = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager

          ./hosts/kaidong-main-desktop/configuration.nix
          ./modules/all.nix
        ];
      };

      nixosConfigurations.Kaidong-MBP14 = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          nix-index-database.nixosModules.nix-index

          ./home/home.nix
          ./hosts/kaidong-mbp14/configuration.nix
          ./modules/all.nix
        ];
      };
    };
}
