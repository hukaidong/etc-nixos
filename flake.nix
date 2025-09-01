{
  description = "A simple NixOS flake";

  inputs = {
    # NixOS official package source, using the nixos-25.05 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager.url = "github:nix-community/home-manager/release-25.05";

    emacs-overlay.url = "github:nix-community/emacs-overlay";
    home.url = "git+file:/home/kaidong/.config/home-manager";
    plover-flake.url = "github:openstenoproject/plover-flake";

    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = inputs@{ nixpkgs, home, home-manager, ... }: {
    # Please replace my-nixos with your hostname
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        # Import the previous configuration.nix we used,
        # so the old configuration file still takes effect
        ./configuration.nix

        home-manager.nixosModules.home-manager
        {
          # configuring emacs overlay so should not use globalPkgs
	  # useGlobalPkgs => true
	  # emacs overlay has no effect, emacs-git is missing from pkgs variable
          home-manager.useGlobalPkgs = false;
	  # zsh can not find completion functions when useUserPackages set to true
	  # useUserPackages => true
	  # zsh functions load in /etc/profiles/per-user/(user)/share/zsh
	  # ${fpath} does not include this path
	  # useUserPackages => false
	  # zsh functions load in ~/.nix-profile/share/zsh
	  # zsh could find those functions
          home-manager.useUserPackages = false;
          home-manager.users.kaidong = "${home}/home.nix";
          home-manager.extraSpecialArgs = {
            inherit (inputs) plover-flake emacs-overlay;
          };
        }
      ];
    };
  };
}
