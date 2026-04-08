{ config, pkgs, ... }:
{
  nix.package = pkgs.nix;
  nix.extraOptions = ''
    !include ${config.sops.secrets."nix-access-tokens".path}
  '';
}
