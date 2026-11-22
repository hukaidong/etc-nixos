{ ... }:
{
  # The nix-darwin system inside the Mac Studio's macOS runner VM. The Mac
  # Studio builds it as part of its own system and its provisioner deploys it
  # into the VM over SSH (darwin/services/github-runner-macos-vm.nix), so
  # nothing is built in the VM. It has no secrets: the runner registers with
  # a short-lived registration token the provisioner hands it.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Fresh nix-darwin release on a Nix 2.34 installer install (nixbld GID 350).
  # Read `darwin-rebuild changelog` before raising it.
  system.stateVersion = 7;

  kaidong-desktop.services.githubRunners = {
    # The runner registers as Kaidong-Mac-Studio-darwin.
    name = "Kaidong-Mac-Studio";
    darwinVM.guest.enable = true;
  };
}
