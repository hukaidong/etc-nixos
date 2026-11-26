# Every nix-darwin option module, imported into every darwin host
# (hosts/darwin.nix). Like ../nixos, each one changes nothing until a host
# enables it; settings that apply on import are in ../../profiles/darwin.
{ lib, ... }:
{
  _class = "darwin";

  imports = lib.filter (path: lib.hasSuffix ".nix" (toString path) && path != ./default.nix) (
    lib.filesystem.listFilesRecursive ./.
  );
}
