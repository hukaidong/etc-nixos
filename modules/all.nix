{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Get all .nix files recursively, excluding all.nix itself
  nixFiles = lib.filesystem.listFilesRecursive ./.;
  moduleFiles = builtins.filter (
    path: lib.hasSuffix ".nix" (toString path) && (toString path) != (toString ./all.nix)
  ) nixFiles;
in

{
  imports = moduleFiles;
}
