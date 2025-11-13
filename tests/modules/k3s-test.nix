{ pkgs, lib, ... }:

let
  testHelpers = import ../lib/test-helpers.nix { inherit pkgs lib; };
in
{
  name = "k3s-module-tests";

  nodes = {
    # Test k3s server configuration
    k3s-server =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/k3s.nix ];
        extraConfig = {
          kaidong-desktop.virtualization.k3s = {
            enable = true;
            isServer = true;
          };
        };
      };

    # Test k3s agent configuration
    k3s-agent =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/k3s.nix ];
        extraConfig = {
          kaidong-desktop.virtualization.k3s = {
            enable = true;
            isServer = false;
          };
        };
      };

    # Test k3s disabled
    k3s-disabled =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/k3s.nix ];
        extraConfig = {
          kaidong-desktop.virtualization.k3s = {
            enable = false;
          };
        };
      };
  };

  testScript =
    { nodes, ... }:
    ''
      import json

      # Test k3s server
      server = nodes["k3s-server"]
      server.wait_for_unit("k3s.service")
      server.succeed("systemctl is-active k3s")

      # Check k3s server role
      server.succeed("grep 'role: server' /etc/systemd/system/k3s.service")

      # Check firewall rules for server
      server.succeed("iptables -L INPUT | grep '6443'")
      server.succeed("iptables -L INPUT | grep '10250'")
      server.succeed("iptables -L INPUT | grep '8472'")

      # Check k3s extra flags
      server.succeed("grep 'write-kubeconfig-mode=644' /etc/systemd/system/k3s.service")

      # Verify k3s is functional
      server.wait_until_succeeds("test -f /etc/rancher/k3s/k3s.yaml")
      server.succeed("kubectl get nodes")

      # Test k3s agent
      agent = nodes["k3s-agent"]
      agent.wait_for_unit("k3s.service")
      agent.succeed("systemctl is-active k3s")

      # Check k3s agent role
      agent.succeed("grep 'role: agent' /etc/systemd/system/k3s.service")

      # Test k3s disabled
      disabled = nodes["k3s-disabled"]
      disabled.fail("systemctl is-active k3s")
      disabled.fail("test -f /etc/rancher/k3s/k3s.yaml")

      # Verify no firewall rules when disabled
      disabled.fail("iptables -L INPUT | grep '6443'")
      disabled.fail("iptables -L INPUT | grep '10250'")
    '';
}
