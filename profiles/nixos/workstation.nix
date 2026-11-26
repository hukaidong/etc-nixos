# Everything my NixOS desktops and laptops run. Importing this file is what
# turns it on (nothing here is gated by an option), so each host lists it in
# its configuration.nix. Option modules, which every host gets and which do
# nothing until enabled, are in ../../modules/nixos.
{
  _class = "nixos";

  imports = [
    ./home-manager.nix
    ./packages/desktop.nix
    ./packages/development.nix
    ./packages/environment.nix
    ./packages/languages.nix
    ./packages/neovim.nix
    ./packages/nix.nix
    ./programs/environment.nix
    ./programs/git.nix
    ./programs/zoom.nix
    ./programs/zsh.nix
    ./security/sops.nix
    ./services/cron.nix
    ./services/journal.nix
    ./services/openssh.nix
    ./services/printing.nix
    ./storage/filesystems.nix
    ./system/audio.nix
    ./system/boot.nix
    ./system/fonts.nix
    ./system/locale.nix
    ./system/misc.nix
    ./system/networking.nix
    ./system/nix-gc.nix
  ];
}
