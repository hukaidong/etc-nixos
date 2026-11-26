{ config, ... }:
{
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/key.txt";
    defaultSopsFile = ../../../secrets/secrets.yaml;
  };

  sops.secrets."nix-access-tokens" = {};
}
