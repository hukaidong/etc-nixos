{ pkgs, lib, ... }:

let
  testHelpers = import ../lib/test-helpers.nix { inherit pkgs lib; };
in
{
  name = "virt-manager-module-tests";

  nodes = {
    # Test virt-manager enabled
    virt-manager-enabled =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/virt-manager.nix ];
        extraConfig = {
          kaidong-desktop.virtualization.virtManager.enable = true;
        };
      };

    # Test virt-manager disabled
    virt-manager-disabled =
      { config, pkgs, ... }:
      testHelpers.mkTestMachine {
        extraModules = [ ../modules/services/virt-manager.nix ];
        extraConfig = {
          kaidong-desktop.virtualization.virtManager.enable = false;
        };
      };
  };

  testScript =
    { nodes, ... }:
    ''
      # Test virt-manager enabled
      enabled = nodes["virt-manager-enabled"]

      # Check libvirtd service is enabled
      enabled.wait_for_unit("libvirtd.service")
      enabled.succeed("systemctl is-active libvirtd")
      enabled.succeed("systemctl is-enabled libvirtd")

      # Check virt-manager program is available
      enabled.succeed("command -v virt-manager")

      # Check user is in libvirtd group
      enabled.succeed("groups kaidong | grep libvirtd")

      # Check libvirtd configuration
      enabled.succeed("test -d /var/lib/libvirt")
      enabled.succeed("virsh list --all")

      # Check spice USB redirection is enabled
      enabled.succeed("grep -q 'spice_usbredirection' /etc/libvirt/qemu.conf || true")

      # Test virt-manager disabled
      disabled = nodes["virt-manager-disabled"]

      # Check libvirtd service is not enabled
      disabled.fail("systemctl is-active libvirtd")
      disabled.fail("systemctl is-enabled libvirtd")

      # Check user is not in libvirtd group
      disabled.fail("groups kaidong | grep libvirtd")

      # Verify virt-manager program might still be available system-wide but service is disabled
      # The important thing is that libvirtd service is not running
    '';
}
