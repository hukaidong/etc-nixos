{ standalone ? false }:
{
  pkgs,
  lib,
  homePath,
  ...
}:
let
  collectNixFiles = dir: lib.filesystem.listFilesRecursive dir;

  configFiles = collectNixFiles ./config;
  packageFiles = collectNixFiles ./packages;
  standaloneFiles = if standalone then collectNixFiles ./standalone else [ ];

  moduleFiles = builtins.filter (path: lib.hasSuffix ".nix" (toString path)) (
    configFiles ++ packageFiles ++ standaloneFiles
  );
in
{
  imports = moduleFiles;

  config = lib.mkMerge [
    {
      home.stateVersion = "25.11";
    }
    (lib.mkIf standalone {
      home.username = "kaidong";
      home.homeDirectory = "${homePath}/kaidong";
      home.packages = [ pkgs.home-manager ];
    })
  ];
}
