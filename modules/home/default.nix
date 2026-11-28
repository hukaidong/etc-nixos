# Every Home Manager option module, imported into every Home Manager user (on
# NixOS through profiles/nixos/home-manager.nix, on the Mac through
# hosts/home.nix). Each one changes nothing until enabled; settings that apply
# on import are in ../../profiles/home.
#
# A module's helpers sit in a directory named after it (foo/ next to foo.nix).
# They are not modules, so they are left out.
{ lib, ... }:
let
  isModule =
    path:
    lib.hasSuffix ".nix" (toString path)
    && path != ./default.nix
    && !builtins.pathExists (dirOf path + ".nix");
in
{
  _class = "homeManager";

  imports = lib.filter isModule (lib.filesystem.listFilesRecursive ./.);
}
