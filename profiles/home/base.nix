# The user environment every machine gets, NixOS and the Mac alike.
{
  _class = "homeManager";

  imports = [
    ./config/dircolors.nix
    ./config/git.nix
    ./config/kitty.nix
    ./config/nix.nix
    ./config/sops.nix
    ./config/zsh.nix
  ];

  home.stateVersion = "25.11";
}
