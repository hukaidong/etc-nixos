# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  desktopEnvironment ? "i3",
  ...
}:
{
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./hardware-configuration.nix
    ./filesystem.nix
    ./users.nix
    ./programs.nix
    ./virtualization.nix
  ];

  networking.hostName = "Kaidong-Main-Desktop";

  boot.kernelPackages = pkgs.linuxPackages_latest;

  programs.steam.enable = true;
  programs.steam.protontricks.enable = true;

  kaidong-desktop.desktopEnvironment.i3.enable = desktopEnvironment == "i3";
  kaidong-desktop.desktopEnvironment.plasma-i3.enable = desktopEnvironment == "plasma-i3";
  kaidong-desktop.desktopEnvironment.plasma6.enable = desktopEnvironment == "plasma6";

  # Autorandr profile for this host's monitor (Samsung C49RG9x ultrawide)
  services.autorandr.profiles.home = {
    fingerprint = {
      HDMI-1 = "00ffffffffffff004c2d9b0f32373930281e0103807722782aa2a1ad4f46a7240e5054bfef80714f810081c08180a9c0b3009500d1c09ecf20a0d0a0465030203a00a9504100001a000000fd0032641ea036000a202020202020000000fc00433439524739780a2020202020000000ff00484e4b4e3930353430360a20200164020321f144905a405b230907078301000067030c001000b83c67d85dc4016c8000023a801871382d40582c4500a9504100001e584d00b8a1381440f82c4500a9504100001e2b7a20a0d0a0295030203a00a9504100001a565e00a0a0a0295030203500a9504100001a0000000000000000000000000000000000000000000033";
    };
    config = {
      HDMI-1 = {
        enable = true;
        primary = true;
        mode = "3360x1440";
        rate = "100.00";
        position = "0x0";
      };
    };
  };

  # Autorandr profile for LG OLED55CC (4K HDR)
  # TODO: Replace fingerprint after connecting the TV (run: autorandr --fingerprint)
  services.autorandr.profiles.oled = {
    fingerprint = {
      HDMI-1 = "00ffffffffffff001e6dcd84010101010124010380a05a780aee91a3544c99260f5054a1080031404540614071408180d1c00101010108e80030f2705a80b0588a0040846300001e6fc200a0a0a055503020350040846300001a000000fd0018781eff77000a202020202020000000fc004c472054562053534352320a20019b020366f15d616076756665dbda101f04130514030212202122155d5e5f6263643f402c0957071507505707016704076e030c004000b8442c0080010203046dd85dc40178806b432878d33305e200cfe305c000e3060d01e20fffeb0146d000480296885c7695565e00a0a0a029503020350040846300001a0000000000000090";
    };
    config = {
      HDMI-1 = {
        enable = true;
        primary = true;
        mode = "3840x2160";
        rate = "60.00";
        position = "0x0";
        dpi = 96;
      };
    };
  };

  system.stateVersion = "25.11";
}
