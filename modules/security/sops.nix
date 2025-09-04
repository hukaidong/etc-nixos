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
}