# Shell snippets of the WireGuard spoke (../wireguard.nix), and the paths
# they use.
{
  config,
  lib,
  pkgs,
}:
let
  cfg = config.kaidong-desktop.networking.wireguard;
  iface = cfg.interface;

  keySecretPath = config.sops.secrets."wireguard-${iface}-private-key".path;
  endpointSecretPath = config.sops.secrets."wireguard-${iface}-endpoint".path;
  endpointFile = lib.escapeShellArg endpointSecretPath;
in
rec {
  key = lib.escapeShellArg cfg.privateKeyFile;
  wg = "${pkgs.wireguard-tools}/bin/wg";

  # The secrets sops-nix decrypts into /run/secrets for the tunnel.
  sopsFiles =
    lib.optional (cfg.privateKeySecret != null) keySecretPath
    ++ lib.optional (cfg.hub.endpointSecret != null) endpointSecretPath;

  setEndpoint =
    interface: ''${wg} set "${interface}" peer ${cfg.hub.publicKey} endpoint "$(cat ${endpointFile})"'';

  # Prints the public key, which goes in the hub's hosts table, and catches
  # the hub's key set to this machine's own (WireGuard then drops the peer).
  printPublicKey = ''
    pub=$(${wg} pubkey < ${key})
    echo "wireguard: ${iface} public key: $pub" >&2
  ''
  + lib.optionalString (cfg.hub.publicKey != null) ''
    if [ "$pub" = ${lib.escapeShellArg cfg.hub.publicKey} ]; then
      echo "wireguard: warning: hub.publicKey is this machine's own public key; the hub's is \`ssh digix sudo wg show ${iface} public-key\`" >&2
    fi
  '';

  # Brings the tunnel up from scratch. The job runs it at boot and whenever
  # activation reloads the job. Naming the config's store path makes this
  # script, and so the job's plist, change whenever the config does, and a
  # changed plist is what makes activation reload the job.
  tunnelUp = pkgs.writeShellScript "wireguard-${iface}-up" (
    ''
      # config: ${config.environment.etc."wireguard/${iface}.conf".source}
    ''
    # At boot sops-install-secrets writes the secrets in its own job, and on
    # a switch activation writes them only after reloading this job.
    + lib.optionalString (sopsFiles != [ ]) ''
      secrets_ready() {
        for f in ${lib.escapeShellArgs sopsFiles}; do
          [ -s "$f" ] || return 1
        done
      }
      for _ in {1..60}; do
        secrets_ready && break
        sleep 1
      done
      if ! secrets_ready; then
        echo "wireguard: still missing after 60 s: ${lib.concatStringsSep ", " sopsFiles}" >&2
        exit 1
      fi
    ''
    + ''
      wg-quick down ${iface} 2>/dev/null || true
      exec wg-quick up ${iface}
    ''
  );
}
