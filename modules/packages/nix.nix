{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    age
    sops
    comma
    nixfmt-rfc-style
    nix-index
  ];
}
