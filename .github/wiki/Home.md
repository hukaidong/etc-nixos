# etc-nixos wiki

Runbooks for the machines this flake manages. The pages live in
`.github/wiki/` in the repository, next to the code they describe, and are
reviewed in pull requests like the code.

- [GitHub runners on the Mac Studio](GitHub-Runners.md): checking on and
  operating the two self-hosted runners (macOS natively on the host, Linux in
  a Colima VM), and the nix-darwin switch pitfalls seen on this machine.
- [WireGuard tunnel to the droplet](WireGuard.md): the private network
  between the Mac Studio and the DigitalOcean droplet (static addresses and
  the `wg.internal` DNS zone), its first-time setup and checking on it.
