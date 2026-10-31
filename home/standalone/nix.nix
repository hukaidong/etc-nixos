{ pkgs, ... }:
{
  home.packages = with pkgs; [
    age
    sops
    nh
    nvd
    nixd
    nixfmt
    devenv
  ];

  programs.nix-index-database.comma.enable = true;
}
