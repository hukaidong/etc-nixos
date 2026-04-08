{
  inputs,
  pkgs,
  ...
}:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.backupFileExtension = "pre-homemanager";

  home-manager.sharedModules = [
    inputs.plover-flake.homeManagerModules.plover
    inputs.sops-nix.homeManagerModules.sops
  ];

  home-manager.extraSpecialArgs =
    let
      pkgs-unstable = import inputs.nixpkgs-unstable {
        inherit (pkgs) system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      inherit pkgs-unstable;
      inherit (inputs) plover-flake;
      homePath = "/home";
    };

  home-manager.users.kaidong = import ./home.nix { standalone = false; };
}
