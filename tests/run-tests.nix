{
  pkgs ? import <nixpkgs> { },
  inputs ? { },
}:

let
  lib = pkgs.lib;

  # Import all test modules
  k3sTest = import ./modules/k3s-test.nix { inherit pkgs lib; };
  virtManagerTest = import ./modules/virt-manager-test.nix { inherit pkgs lib; };
  virtualisationTest = import ./modules/virtualisation-test.nix { inherit pkgs lib; };
  integrationTest = import ./modules/integration-test.nix { inherit pkgs lib; };

  # Create test driver for each test
  makeTest = test: (pkgs.nixosTest test);

in
# Return the main test derivation
pkgs.nixosTest {
  name = "virtualization-module-tests";

  nodes = {
    # Test complete virtualization stack
    full-stack =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/services/virtualisation.nix
          ../modules/services/k3s.nix
          ../modules/services/virt-manager.nix
        ];

        # Minimal base configuration for testing
        users.users.kaidong = {
          isNormalUser = true;
          description = "Test User";
          group = "users";
        };

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

  testScript = ''
    start_all()

    # Test that all virtualization components are working
    machine = full_stack

    # Wait for services to start
    machine.wait_for_unit("docker.service")
    machine.wait_for_unit("libvirtd.service")

    # Give k3s more time to start
    machine.wait_for_unit("k3s.service", timeout=120)

    # Verify services are active
    machine.succeed("systemctl is-active docker")
    machine.succeed("systemctl is-active k3s")
    machine.succeed("systemctl is-active libvirtd")

    # Verify packages are available
    machine.succeed("command -v docker")
    machine.succeed("command -v podman")
    machine.succeed("command -v kubectl")
    machine.succeed("command -v helm")
    machine.succeed("command -v devcontainer")
    machine.succeed("command -v podman-compose")
    machine.succeed("command -v virt-manager")

    # Verify user permissions
    machine.succeed("groups kaidong | grep libvirtd")

    # Verify k3s configuration exists
    machine.wait_until_succeeds("test -f /etc/rancher/k3s/k3s.yaml", timeout=60)

    # Verify Docker functionality
    machine.succeed("docker --version")

    # Verify k3s is running (basic check)
    machine.succeed("systemctl status k3s | grep -q 'active (running)'")

    print("✅ All virtualization module tests passed!")
  '';
}
