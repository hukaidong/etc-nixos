{ inputs, ... }:
{
  # System layer only (nix-darwin). User-level config is the standalone
  # home-manager configuration homeConfigurations.Kaidong-Mac-Studio.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # nix-darwin release whose stateful defaults this machine was set up with
  # (nixbld GID 350 matches the official installer). Read
  # `darwin-rebuild changelog` before raising it.
  system.stateVersion = 7;

  nix.settings.trusted-users = [ "kaidong" ];

  # nix-darwin owns /etc/pam.d/sudo_local; this keeps the Touch ID for sudo
  # that the hand-edited file enabled before.
  security.pam.services.sudo_local.touchIdAuth = true;

  # Runners for the kd-lapwings org, both in VMs on the RunnerVMs volume (an
  # external SSD) and started at boot: Kaidong-Mac-Studio-darwin in a macOS
  # VM (Tart) running the nix-darwin system Kaidong-Mac-Studio-runner-vm
  # (hosts/kaidong-mac-studio-runner-vm), and Kaidong-Mac-Studio-linux (a
  # container per job in a Colima VM). The organization token is
  # `github-runner-token` in secrets/secrets.yaml and stays on this machine.
  kaidong-desktop.services.githubRunners = {
    name = "Kaidong-Mac-Studio";
    stateRoot = "/Volumes/RunnerVMs";
    # Six cores each: the VMs share the Mac Studio's twelve with each other
    # and the host, and 20 of its 32 GiB.
    darwinVM = {
      enable = true;
      system = inputs.self.darwinConfigurations.Kaidong-Mac-Studio-runner-vm;
      cpus = 6;
      memory = 10;
      disk = 150;
    };
    linux = {
      enable = true;
      cpus = 6;
      memory = 10;
    };
  };
}
