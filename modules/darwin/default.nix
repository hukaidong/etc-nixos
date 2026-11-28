# Every nix-darwin option module, imported into every darwin host
# (hosts/darwin.nix). Like ../nixos, each one changes nothing until a host
# enables it; settings that apply on import are in ../../profiles/darwin.
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
  _class = "darwin";

  imports = lib.filter isModule (lib.filesystem.listFilesRecursive ./.);
}
