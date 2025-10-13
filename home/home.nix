{
  inputs,
  pkgs,
  lib,
  ...
}:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.backupFileExtension = "pre-homemanager";

  home-manager.sharedModules = [
    inputs.plover-flake.homeManagerModules.plover
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

  home-manager.users.kaidong =
    { pkgs, ... }:
    let
      # Get all .nix files recursively, excluding all.nix itself
      nixFiles = lib.filesystem.listFilesRecursive ./.;
      moduleFiles = builtins.filter (
        path: lib.hasSuffix ".nix" (toString path) && (toString path) != (toString ./home.nix)
      ) nixFiles;
    in
    {
      imports = moduleFiles;

      home.stateVersion = "25.05";
    };
}
