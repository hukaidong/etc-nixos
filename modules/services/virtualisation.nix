{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    docker
    devcontainer
    kubernetes
    podman-compose
  ];

  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;
}
