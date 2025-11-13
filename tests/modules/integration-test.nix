{ pkgs, lib, ... }:

let
  testHelpers = import ../lib/test-helpers.nix { inherit pkgs lib; };
in
{
  name = "virtualization-integration-tests";

  nodes = {
    # Test complete virtualization stack (like current host config)
    full-stack =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraConfig = {
          # Import all virtualization modules
          imports = [
            ../modules/services/virtualisation.nix
            ../modules/services/k3s.nix
            ../modules/services/virt-manager.nix
          ];

          # Enable all virtualization components (matching host config)
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
          };
        };
      };

    # Test minimal virtualization setup
    minimal-stack =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraConfig = {
          imports = [
            ../modules/services/virtualisation.nix
          ];

          kaidong-desktop.virtualization = {
            docker.enable = true;
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
      # Test full stack integration
      full = nodes["full-stack"]

      # Wait for all services to start
      full.wait_for_unit("docker.service")
      full.wait_for_unit("k3s.service")
      full.wait_for_unit("libvirtd.service")

      # Verify all services are active
      full.succeed("systemctl is-active docker")
      full.succeed("systemctl is-active k3s")
      full.succeed("systemctl is-active libvirtd")

      # Verify all packages are available
      full.succeed("command -v docker")
      full.succeed("command -v podman")
      full.succeed("command -v kubectl")
      full.succeed("command -v helm")
      full.succeed("command -v devcontainer")
      full.succeed("command -v podman-compose")
      full.succeed("command -v virt-manager")

      # Verify user permissions
      full.succeed("groups kaidong | grep libvirtd")

      # Verify k3s functionality
      full.wait_until_succeeds("test -f /etc/rancher/k3s/k3s.yaml")
      full.succeed("kubectl get nodes")

      # Verify Docker functionality
      full.succeed("docker --version")
      full.succeed("docker info")

      # Verify Podman functionality
      full.succeed("podman --version")

      # Verify firewall rules for k3s
      full.succeed("iptables -L INPUT | grep '6443'")
      full.succeed("iptables -L INPUT | grep '10250'")

      # Test minimal stack
      minimal = nodes["minimal-stack"]

      # Wait for Docker service
      minimal.wait_for_unit("docker.service")
      minimal.succeed("systemctl is-active docker")

      # Verify Docker is available
      minimal.succeed("command -v docker")
      minimal.succeed("docker --version")

      # Verify other services are not running
      minimal.fail("systemctl is-active k3s")
      minimal.fail("systemctl is-active libvirtd")

      # Verify other packages are not installed
      minimal.fail("command -v kubectl")
      minimal.fail("command -v podman")
      minimal.fail("command -v virt-manager")

      # Verify no k3s firewall rules
      minimal.fail("iptables -L INPUT | grep '6443'")
      minimal.fail("iptables -L INPUT | grep '10250'")

      # Test service dependencies and startup order
      # Docker should start before containers can be managed
      full.succeed("docker run --rm hello-world")

      # k3s should be functional for Kubernetes operations
      full.succeed("kubectl cluster-info")

      # libvirtd should be ready for VM operations
      full.succeed("virsh list --all")
    '';
}
