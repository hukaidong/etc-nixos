{ pkgs, lib, ... }:

let
  testHelpers = import ../lib/test-helpers.nix { inherit pkgs lib; };
in
{
  name = "shutdown-inhibit-tests";

  nodes = {
    # Test X11 mode - xdotool should be available
    x11-mode =
      { config, pkgs, ... }:
      {
        imports = [ ../../modules/services/shutdown-inhibit.nix ];

        # Enable X11
        services.xserver.enable = true;

        # Enable shutdown inhibitor
        services.shutdownInhibit = {
          enable = true;
          startHour = 9;
          endHour = 23;
        };
      };

    # Test Wayland mode - ydotool should be available
    wayland-mode =
      { config, pkgs, ... }:
      {
        imports = [ ../../modules/services/shutdown-inhibit.nix ];

        # Disable X11 (Wayland mode)
        services.xserver.enable = false;

        # Enable a Wayland compositor for the assertion
        services.desktopManager.plasma6.enable = true;

        # Enable shutdown inhibitor
        services.shutdownInhibit = {
          enable = true;
          startHour = 9;
          endHour = 23;
        };
      };
  };

  testScript = ''
    # Test X11 mode
    x11_mode.start()
    x11_mode.wait_for_unit("multi-user.target")

    # Verify xdotool is installed
    x11_mode.succeed("command -v xdotool")

    # Verify shutdown-inhibit services exist
    x11_mode.succeed("systemctl cat shutdown-inhibit.service")
    x11_mode.succeed("systemctl cat shutdown-inhibit-boot-check.service")
    x11_mode.succeed("systemctl cat shutdown-inhibit-start.service")
    x11_mode.succeed("systemctl cat shutdown-inhibit-stop.service")

    # Verify timers exist
    x11_mode.succeed("systemctl cat shutdown-inhibit-start.timer")
    x11_mode.succeed("systemctl cat shutdown-inhibit-stop.timer")

    print("✅ X11 mode tests passed!")

    # Test Wayland mode
    wayland_mode.start()
    wayland_mode.wait_for_unit("multi-user.target")

    # Verify ydotool is installed
    wayland_mode.succeed("command -v ydotool")

    # Verify ydotoold service exists
    wayland_mode.succeed("systemctl cat ydotoold.service")

    # Verify shutdown-inhibit services exist
    wayland_mode.succeed("systemctl cat shutdown-inhibit.service")
    wayland_mode.succeed("systemctl cat shutdown-inhibit-boot-check.service")
    wayland_mode.succeed("systemctl cat shutdown-inhibit-start.service")
    wayland_mode.succeed("systemctl cat shutdown-inhibit-stop.service")

    # Verify timers exist
    wayland_mode.succeed("systemctl cat shutdown-inhibit-start.timer")
    wayland_mode.succeed("systemctl cat shutdown-inhibit-stop.timer")

    print("✅ Wayland mode tests passed!")
  '';
}
