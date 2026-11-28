{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf optionals;

  cfg = config.kaidong-desktop.virtualization;
in
{
  options.kaidong-desktop.virtualization = {
    docker.enable = mkEnableOption "Docker container runtime";

    podman.enable = mkEnableOption "Podman container runtime";

    devcontainer.enable = mkEnableOption "DevContainer support";

    podmanCompose.enable = mkEnableOption "Podman Compose";

    distrobox.enable = mkEnableOption "Distrobox";

  };

  config = {
    assertions = [
      {
        assertion = !cfg.podmanCompose.enable || cfg.podman.enable;
        message = "podmanCompose.enable requires podman.enable to be true";
      }
      {
        assertion = !cfg.distrobox.enable || cfg.podman.enable;
        message = "distrobox.enable requires podman.enable to be true";
      }
    ];

    environment.systemPackages =
      with pkgs;
      (optionals cfg.docker.enable [ docker ])
      ++ (optionals cfg.devcontainer.enable [ devcontainer ])
      ++ (optionals cfg.podmanCompose.enable [ podman-compose ])
      ++ (optionals cfg.distrobox.enable [ distrobox ]);

    # mkIf, not `= cfg.docker.enable`: setting `false` here would conflict with
    # a host that sets virtualisation.docker.enable itself.
    virtualisation.docker.enable = mkIf cfg.docker.enable true;
    virtualisation.podman.enable = mkIf cfg.podman.enable true;
  };
}
