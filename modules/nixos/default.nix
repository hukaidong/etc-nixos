# Every NixOS option module, imported into every NixOS host (hosts/nixos.nix).
# Each one declares options under `kaidong-desktop.` and changes nothing until
# a host enables it, which is what makes importing all of them safe. Settings
# that apply as soon as they are imported are profiles, in ../../profiles/nixos,
# and hosts import those by name.
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
  _class = "nixos";

  imports = lib.filter isModule (lib.filesystem.listFilesRecursive ./.);
}
