{ pkgs, ... }:
{
  home.packages = with pkgs; [
    age
    sops
    nvd
    nixd
    nixfmt
    devenv
  ];

  programs.nix-index-database.comma.enable = true;
}
