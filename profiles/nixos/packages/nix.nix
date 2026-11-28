{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    age
    sops
    comma
    nh
    nvd
    nixd
    nixfmt
    nix-index
  ];
}
