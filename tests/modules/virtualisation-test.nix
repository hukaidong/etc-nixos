{ pkgs, lib, ... }:

let
  testHelpers = import ../lib/test-helpers.nix { inherit pkgs lib; };
in
{
  name = "virtualisation-module-tests";

  nodes = {
    # Test all virtualization components enabled
    all-enabled =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/virtualisation.nix ];
        extraConfig = {
          kaidong-desktop.virtualization = {
            docker.enable = true;
            kubernetes.enable = true;
            podman.enable = true;
            devcontainer.enable = true;
            podmanCompose.enable = true;
          };
        };
      };

    # Test only Docker enabled
    docker-only =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/virtualisation.nix ];
        extraConfig = {
          kaidong-desktop.virtualization = {
            docker.enable = true;
            kubernetes.enable = false;
            podman.enable = false;
            devcontainer.enable = false;
            podmanCompose.enable = false;
          };
        };
      };

    # Test only Podman enabled
    podman-only =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/virtualisation.nix ];
        extraConfig = {
          kaidong-desktop.virtualization = {
            docker.enable = false;
            kubernetes.enable = false;
            podman.enable = true;
            devcontainer.enable = false;
            podmanCompose.enable = false;
          };
        };
      };

    # Test all disabled
    all-disabled =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/virtualisation.nix ];
        extraConfig = {
          kaidong-desktop.virtualization = {
            docker.enable = false;
            kubernetes.enable = false;
            podman.enable = false;
            devcontainer.enable = false;
            podmanCompose.enable = false;
          };
        };
      };
  };

  testScript =
    { nodes, ... }:
    ''
      # Test all enabled
      all_enabled = nodes["all-enabled"]

      # Check Docker
      all_enabled.wait_for_unit("docker.service")
      all_enabled.succeed("systemctl is-active docker")
      all_enabled.succeed("command -v docker")

      # Check Podman
      all_enabled.succeed("command -v podman")

      # Check Kubernetes packages
      all_enabled.succeed("command -v kubectl")
      all_enabled.succeed("command -v helm")

      # Check DevContainer
      all_enabled.succeed("command -v devcontainer")

      # Check Podman Compose
      all_enabled.succeed("command -v podman-compose")

      # Test Docker only
      docker_only = nodes["docker-only"]

      docker_only.wait_for_unit("docker.service")
      docker_only.succeed("systemctl is-active docker")
      docker_only.succeed("command -v docker")

      # Verify other components are not installed
      docker_only.fail("command -v podman")
      docker_only.fail("command -v kubectl")
      docker_only.fail("command -v devcontainer")
      docker_only.fail("command -v podman-compose")

      # Test Podman only
      podman_only = nodes["podman-only"]

      podman_only.succeed("command -v podman")

      # Verify other components are not installed
      podman_only.fail("systemctl is-active docker")
      podman_only.fail("command -v docker")
      podman_only.fail("command -v kubectl")
      podman_only.fail("command -v devcontainer")
      podman_only.fail("command -v podman-compose")

      # Test all disabled
      all_disabled = nodes["all-disabled"]

      # Verify no container runtimes are active
      all_disabled.fail("systemctl is-active docker")
      all_disabled.fail("command -v docker")
      all_disabled.fail("command -v podman")
      all_disabled.fail("command -v kubectl")
      all_disabled.fail("command -v helm")
      all_disabled.fail("command -v devcontainer")
      all_disabled.fail("command -v podman-compose")
    '';
}
