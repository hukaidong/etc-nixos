{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    docker
    devcontainer
    kubernetes
    kubernetes-helm
    podman-compose
  ];

  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--write-kubeconfig-mode=644"
    ];
  };
}
