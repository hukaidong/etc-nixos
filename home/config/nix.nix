{ config, pkgs, ... }:
{
  nix.package = pkgs.nix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.extraOptions = ''
    !include ${config.sops.secrets."nix-access-tokens".path}
  '';
}
