{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    age
    sops
    comma
    nvd
    nixd
    nixfmt
    nix-index
  ];
}
