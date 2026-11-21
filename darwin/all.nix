{
  config,
  pkgs,
  lib,
  ...
}:

# nix-darwin counterpart of modules/all.nix: every .nix file under darwin/ is
# part of every darwinConfiguration. Gate module bodies on an option so hosts
# opt in from hosts/<name>/configuration.nix.
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
