# Virtualization configuration for kaidong-main-desktop
# This replaces the hardcoded virtualisation.nix module with configurable options

{
  kaidong-desktop.virtualization = {
    docker.enable = true;

    kubernetes.enable = true;

    k3s = {
      enable = true;
      isServer = true;
    };

    podman.enable = true;

    devcontainer.enable = true;

    podmanCompose.enable = true;

    virtManager.enable = true;

    distrobox.enable = true;
  };
}
