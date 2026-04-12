{ pkgs, ... }:
{
  home.packages = with pkgs; [
    age
    sops
    nvd
    nixd
    nixfmt-rfc-style
    devenv
  ];

  programs.nix-index-database.comma.enable = true;
}
