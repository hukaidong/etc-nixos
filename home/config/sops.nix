{
  pkgs,
  lib,
  config,
  homePath,
  ...
}:
{
  sops = {
    age.keyFile = "${homePath}/${config.home.username}/.config/sops/age/key.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
  };

  sops.secrets."nix-access-tokens" = {};
}
