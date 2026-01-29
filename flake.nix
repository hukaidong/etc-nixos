{
  description = "Modular NixOS configuration managing multiple machines with shared infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-ruby.url = "github:bobvanderlinden/nixpkgs-ruby";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    fakwin.url = "github:DMaroo/fakwin";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    nix-index-database.url = "github:nix-community/nix-index-database";
    plover-flake.url = "github:openstenoproject/plover-flake";
    sops-nix.url = "github:Mic92/sops-nix";
    fontconfig.url = "github:hukaidong/flake-fonts";

    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fakwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-index-database,
      fakwin,
      ...
    }:
    let
      extraPkgsOverlay = {
        nixpkgs.overlays = [
          (
            final: prev:
            let
              system = final.stdenv.hostPlatform.system;
            in
            {
              # Custom package collections
              unstable = import inputs.nixpkgs-unstable {
                inherit system;
                config.allowUnfree = true;
              };
              ai-tools = inputs.nix-ai-tools.packages.${system};

              # Custom packages
              ruby-custom = (inputs.nixpkgs-ruby.packages.${system}."ruby-4.0.0").override {
                docSupport = true;
              };
              myfonts = inputs.fontconfig.packages.${system}.default;
            }
          )
        ];
      };

      sysRevConfig = {
        system.configurationRevision = self.rev or self.dirtyRev or null;
      };

      commonNixModules = with inputs; [
        extraPkgsOverlay
        sysRevConfig
        fakwin.nixosModules.default
        home-manager.nixosModules.home-manager
        sops-nix.nixosModules.sops
      ];
      mkUpdateCommand =
        pkgs:
        pkgs.writeShellScriptBin "update" ''
          set -e
          nix flake update
          git commit -am "chore: Update flake.lock"
          git push
        '';
    in
    {
      devShells.x86_64-linux.default =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          update-command = mkUpdateCommand pkgs;
        in
        pkgs.mkShell {
          packages = [ update-command ];
          shellHook = ''
            echo "NixOS config shell loaded. Run 'update' to update flake.lock and push."
          '';
        };

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
