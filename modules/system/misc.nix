{ config, ... }:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.extraOptions = ''
    !include ${config.sops.secrets."nix-access-tokens".path}
  '';

  nix.settings.trusted-users = [ "kaidong" ];
  nix.settings.secret-key-files = [ "/etc/nix/digix-nix.key" ];
}
