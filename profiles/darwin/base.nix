# What every nix-darwin machine runs: the Nix daemon's settings and the
# system-level secrets. Importing this file is what turns them on.
{
  _class = "darwin";

  imports = [
    ./security/sops.nix
    ./system/nix.nix
  ];
}
