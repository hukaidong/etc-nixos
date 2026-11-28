{ config, pkgs, ... }:
{
  nix = {
    package = pkgs.lib.mkDefault pkgs.nix;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    extraOptions = ''
      !include ${config.sops.secrets."nix-access-tokens".path}
    '';
  };
}
