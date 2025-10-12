{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    kubernetes
    podman-compose
  ];

  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;
}
