{ pkgs, ... }:
{
  home.packages = with pkgs; [
    age
    sops
    comma
    nvd
    nixd
    nixfmt-rfc-style
    nix-index
  ];
}
