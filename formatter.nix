# `nix fmt`, one per platform this flake manages: treefmt running deadnix,
# statix and nixfmt over every Nix file, by the rules in treefmt.nix.
{ nixpkgs, treefmt-nix, ... }:
nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
  system:
  (treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix).config.build.wrapper
)
