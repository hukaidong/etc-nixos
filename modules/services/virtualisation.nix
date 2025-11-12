{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.kaidong-desktop.virtualization;
in
{
  options.kaidong-desktop.virtualization = {
    docker.enable = mkEnableOption "Docker container runtime";

    kubernetes.enable = mkEnableOption "Kubernetes tools and packages";

    podman.enable = mkEnableOption "Podman container runtime";

    devcontainer.enable = mkEnableOption "DevContainer support";

    podmanCompose.enable = mkEnableOption "Podman Compose";

  };

  config = {
    environment.systemPackages =
      with pkgs;
      (optionals cfg.docker.enable [ docker ])
      ++ (optionals cfg.devcontainer.enable [ devcontainer ])
      ++ (optionals cfg.kubernetes.enable [
        kubernetes
        kubernetes-helm
      ])
      ++ (optionals cfg.podmanCompose.enable [ podman-compose ]);

    virtualisation.docker.enable = cfg.docker.enable;
    virtualisation.podman.enable = cfg.podman.enable;

  };
}
