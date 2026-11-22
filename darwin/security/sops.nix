{ config, lib, ... }:
{
  # System-level secrets, decrypted by root into /run/secrets at activation and
  # again at boot by the sops-install-secrets launchd daemon. Same key location
  # as the NixOS hosts (modules/security/sops.nix): a file under /etc is
  # readable by boot-time daemons, unlike one under the user's home.
  #
  # Modules declare their own secrets here, e.g. the runners' organization
  # token in darwin/services/github-runner-linux.nix. A system without secrets
  # (the macOS runner VM) gets no sops setup at all, and needs no age key.
  config = lib.mkIf (config.sops.secrets != { }) {
    sops = {
      age.keyFile = "/etc/sops/age/key.txt";
      age.sshKeyPaths = [ ];
      gnupg.sshKeyPaths = [ ];
      defaultSopsFile = ../../secrets/secrets.yaml;
    };
  };
}
