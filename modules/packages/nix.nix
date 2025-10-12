{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    age
    sops
    nixfmt-rfc-style
    nix-index
  ];
}
