{ ... }:
{
  sops = {
    age.keyFile = "/etc/sops/age/key.txt";
    defaultSopsFile = ./../../secrets/secrets.yaml;
  };

  sops.secrets."davfs-credentials" = {
    path = "/etc/davfs2/secrets";
    mode = "0600";
    owner = "root";
  };

  sops.secrets."keechain-credentials" = {
    mode = "0400";
    owner = "kaidong";
  };

  sops.secrets."digix-nix-key" = {
    path = "/etc/nix/digix-nix.key";
    mode = "0400";
    owner = "root";
  };

  sops.secrets."nix-access-tokens" = {
    path = "/etc/nix/nixAccessToken";
    mode = "0400";
    owner = "root";
  };

  sops.secrets."nix-access-tokens-user" = {
    key = "nix-access-tokens";
    mode = "0400";
    owner = "kaidong";
  };
}
