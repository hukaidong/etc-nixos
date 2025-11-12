{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    age
    sops
    comma
    nvd
    nixfmt-rfc-style
    nix-index
  ];
}
