# Every NixOS option module, imported into every NixOS host (hosts/nixos.nix).
# Each one declares options under `kaidong-desktop.` and changes nothing until
# a host enables it, which is what makes importing all of them safe. Settings
# that apply as soon as they are imported are profiles, in ../../profiles/nixos,
# and hosts import those by name.
{ lib, ... }:
{
  _class = "nixos";

  imports = lib.filter (path: lib.hasSuffix ".nix" (toString path) && path != ./default.nix) (
    lib.filesystem.listFilesRecursive ./.
  );
}
