# Common test utilities for virtualization module testing

{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types;
in
{
  # Helper to create a minimal test machine configuration
  mkTestMachine =
    {
      extraModules ? [ ],
      extraConfig ? { },
      ...
    }:
    {
      # extraConfig is a module of its own rather than `// extraConfig`, which
      # would replace whole top-level attributes such as `users`.
      imports = extraModules ++ [ extraConfig ];

      # Minimal base configuration for testing
      users.users.kaidong = {
        isNormalUser = true;
        description = "Test User";
        group = "users";
      };
    };

  # Helper to test module options evaluation
  evalModule =
    module:
    lib.evalModules {
      modules = [
        module
        {
          _module.check = false; # Disable module checks for testing
        }
      ];
      specialArgs = { inherit pkgs lib; };
    };

  # Helper to check if service is enabled
  assertServiceEnabled = serviceName: machine: ''
    machine.wait_for_unit("${serviceName}")
    machine.succeed("systemctl is-active ${serviceName}")
  '';

  # Helper to check if service is disabled
  assertServiceDisabled = serviceName: machine: ''
    machine.fail("systemctl is-active ${serviceName}")
  '';

  # Helper to check package installation
  assertPackageInstalled = packageName: machine: ''
    machine.succeed("command -v ${packageName}")
  '';

  # Helper to check package not installed
  assertPackageNotInstalled = packageName: machine: ''
    machine.fail("command -v ${packageName}")
  '';

  # Helper to check firewall rules
  assertFirewallPort = port: protocol: machine: ''
    machine.succeed("iptables -L INPUT | grep -E '${protocol}\\s+${port}'")
  '';

  # Helper to check user group membership
  assertUserInGroup = user: group: machine: ''
    machine.succeed("groups ${user} | grep ${group}")
  '';
}
