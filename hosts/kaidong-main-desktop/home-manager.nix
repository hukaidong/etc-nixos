{ inputs, pkgs, ... }:
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
  home-manager.users.kaidong = "${inputs.home}/home.nix";
  home-manager.sharedModules = [
    inputs.plover-flake.homeManagerModules.plover
  ];
  home-manager.extraSpecialArgs =
    let
      nix-ai-tools-pkgs = inputs.nix-ai-tools.packages.${pkgs.system};
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit (pkgs) system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      inherit nix-ai-tools-pkgs;
      inherit pkgs-unstable;
      inherit (inputs) plover-flake emacs-overlay;
      homePath = "/home";
    };
}
