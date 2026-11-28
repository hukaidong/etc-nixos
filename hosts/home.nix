# Standalone Home Manager: the user layer of machines whose system is not
# NixOS. NixOS hosts get theirs through profiles/nixos/home-manager.nix.
inputs@{ self, nixpkgs, ... }:
{
  Kaidong-Mac-Studio = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      system = "aarch64-darwin";
      config.allowUnfree = true;
      overlays = [ self.overlays.default ];
    };
    modules = [
      ../profiles/home/base.nix
      ../modules/home
      ../profiles/home/darwin.nix
      inputs.plover-flake.homeManagerModules.plover
      inputs.sops-nix.homeManagerModules.sops
      inputs.nix-index-database.homeModules.default
    ];
  };
}
