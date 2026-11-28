{ config, ... }:
{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [ "kaidong" ];
      secret-key-files = [ "/etc/nix/digix-nix.key" ];
    };

    extraOptions = ''
      !include ${config.sops.secrets."nix-access-tokens".path}
    '';
  };
}
