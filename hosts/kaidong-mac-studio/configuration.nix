{
  # System layer only (nix-darwin). User-level config is the standalone
  # home-manager configuration homeConfigurations.Kaidong-Mac-Studio.
  imports = [ ../../profiles/darwin/base.nix ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  # nix-darwin release whose stateful defaults this machine was set up with
  # (nixbld GID 350 matches the official installer). Read
  # `darwin-rebuild changelog` before raising it.
  system.stateVersion = 7;

  # nix-darwin owns /etc/pam.d/sudo_local; this keeps the Touch ID for sudo
  # that the hand-edited file enabled before.
  security.pam.services.sudo_local.touchIdAuth = true;

  # Runners for the kd-lapwings org: Kaidong-Mac-Studio-darwin (native) and
  # Kaidong-Mac-Studio-linux (a container per job in a Colima VM). Both start
  # at boot; the token is `github-runner-token` in secrets/secrets.yaml.
  kaidong-desktop.services.githubRunners = {
    name = "Kaidong-Mac-Studio";
    darwin.enable = true;
    linux = {
      enable = true;
      # Half the Mac Studio's 12 cores; the macOS runner shares the host.
      cpus = 6;
      memory = 12;
    };
  };

  # Tunnel to the DigitalOcean droplet (nixos-lab is the hub): this machine is
  # mac-studio.wg.internal at the address below, which must match its entry
  # in nixos-lab's hosts table. This machine's private key and the hub's
  # `IP:port` are `wireguard-mac-studio-private-key` and
  # `wireguard-hub-endpoint` in secrets/secrets.yaml. See
  # .github/wiki/WireGuard.md.
  kaidong-desktop.networking.wireguard = {
    enable = true;
    address = "10.77.0.2";
    privateKeySecret = "wireguard-mac-studio-private-key";
    hub = {
      publicKey = "La77HxNKrh5nw1+rW3lOcvw/vnefyeWyleOs+abFhnI=";
      endpointSecret = "wireguard-hub-endpoint";
    };
  };
}
