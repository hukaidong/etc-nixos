{ config, ... }:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.extraOptions = ''
    extra-substituters = https://devenv.cachix.org
    extra-trusted-public-keys = devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=
    !include ${config.sops.secrets."nix-access-tokens".path}
  '';

  nix.settings.secret-key-files = [ "/etc/nix/digix-nix.key" ];
}
