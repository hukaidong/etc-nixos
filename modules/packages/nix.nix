{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    age
    sops
    comma
    nvd
    nixd
    nixfmt-rfc-style
    nix-index
  ];
}
