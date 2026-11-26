# Every Home Manager option module, imported into every Home Manager user (on
# NixOS through profiles/nixos/home-manager.nix, on the Mac through
# hosts/home.nix). Each one changes nothing until enabled; settings that apply
# on import are in ../../profiles/home.
{ lib, ... }:
{
  _class = "homeManager";

  imports = lib.filter (path: lib.hasSuffix ".nix" (toString path) && path != ./default.nix) (
    lib.filesystem.listFilesRecursive ./.
  );
}
