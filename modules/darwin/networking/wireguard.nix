{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.networking.wireguard;
  iface = cfg.interface;

  # Secrets decrypted by sops-nix into /run/secrets, as opposed to a key
  # created on the machine and an endpoint written into the store.
  keyFromSops = cfg.privateKeySecret != null;
  endpointFromSops = cfg.hub.endpointSecret != null;
  # Until the hub's key and endpoint are known, the tunnel is not configured.
  hubKnown = cfg.hub.publicKey != null && (cfg.hub.endpoint != null || endpointFromSops);
in
{
  # Spoke of the WireGuard network whose hub is the DigitalOcean droplet
  # (nixos-lab, nixlab.networking.wireguard). This machine dials the hub and
  # gets a static address in `subnet`; names under `domain` resolve through
  # the hub's DNS over the tunnel, and only those names (split DNS).
  options.kaidong-desktop.networking.wireguard = {
    enable = lib.mkEnableOption "the WireGuard tunnel to the nixos-lab hub";

    address = lib.mkOption {
      type = lib.types.str;
      example = "10.77.0.2";
      description = ''
        This machine's tunnel address. It must match the machine's entry in
        the hub's `nixlab.networking.wireguard.hosts` table in nixos-lab.
      '';
    };

    interface = lib.mkOption {
      type = lib.types.strMatching "[a-zA-Z0-9_=+.-]{1,15}";
      default = "wg0";
      description = ''
        wg-quick name of the tunnel. macOS calls the interface utunN;
        /var/run/wireguard/<name>.name holds which one.
      '';
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "10.77.0.0/24";
      description = "The tunnel network. Only it is routed through the tunnel.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "wg.internal";
      description = "DNS zone the hub serves for the tunnel's hosts.";
    };

    hub = {
      address = lib.mkOption {
        type = lib.types.str;
        default = "10.77.0.1";
        description = "The hub's tunnel address; it also serves {option}`domain`.";
      };

      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          The hub's public key (`ssh digix sudo wg show wg0 public-key`).
          Until it and the endpoint ({option}`hub.endpoint` or
          {option}`hub.endpointSecret`) are set, the tunnel is not
          configured; activation still creates this machine's key.
        '';
      };

      endpoint = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "203.0.113.7:51820";
        description = ''
          Public `address:port` of the hub. Use the droplet's IP (or a
          Reserved IP) rather than a name: an IP needs no DNS when the tunnel
          comes up at boot, and a Cloudflare-proxied name cannot carry
          WireGuard's UDP at all.
        '';
      };

      endpointSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "wireguard-hub-endpoint";
        description = ''
          Key in secrets/secrets.yaml holding {option}`hub.endpoint`'s value,
          which keeps the hub's address out of the repository. Set this or
          {option}`hub.endpoint`, not both. The tunnel sets the endpoint from
          the decrypted secret when it comes up, so at boot it waits for
          sops-install-secrets; activation applies a changed value to the
          running tunnel.
        '';
      };
    };

    persistentKeepalive = lib.mkOption {
      type = lib.types.ints.between 1 65535;
      default = 25;
      description = ''
        Seconds between keepalives to the hub. They keep this machine's NAT
        mapping open, so the hub can reach it at any time.
      '';
    };

    privateKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "wireguard-mac-studio-private-key";
      description = ''
        Key in secrets/secrets.yaml holding this machine's private key (the
        output of `wg genkey`), so a reinstalled machine keeps its identity
        and the hub's hosts table needs no change. When set, it is
        {option}`privateKeyFile`'s default, activation creates no key, and at
        boot the tunnel waits for sops-install-secrets; activation applies a
        changed key to the running tunnel. When null, activation creates the
        key on the machine.
      '';
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.str;
      default =
        if keyFromSops then
          config.sops.secrets."wireguard-${iface}-private-key".path
        else
          "/var/lib/wireguard/${iface}.key";
      defaultText = lib.literalMD ''
        the decrypted {option}`privateKeySecret` if set, else
        `/var/lib/wireguard/<interface>.key`
      '';
      description = ''
        This machine's private key. Unless it comes from
        {option}`privateKeySecret`, activation creates it with `wg genkey` if
        it does not exist, and then it never leaves the machine. Activation
        prints the public key, which goes in the hub's hosts table.
      '';
    };

    dns.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Send lookups under {option}`domain` to the hub, through
        /etc/resolver/<domain>. Other lookups are unaffected. Tools that
        bypass the system resolver, such as `dig` and `nslookup`, ignore it.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      scripts = import ./wireguard/scripts.nix { inherit config lib pkgs; };
      inherit (scripts) key wg;
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.hub.endpoint == null || cfg.hub.endpointSecret == null;
            message = "kaidong-desktop.networking.wireguard: set hub.endpoint or hub.endpointSecret, not both.";
          }
        ];

        warnings = lib.optional (!hubKnown) ''
          kaidong-desktop.networking.wireguard: hub.publicKey and an endpoint
          (hub.endpoint or hub.endpointSecret) are not both set, so the tunnel
          is not configured yet. Activation still prints this machine's public
          key (and creates the key, unless it comes from privateKeySecret).
        '';

        environment.systemPackages = [ pkgs.wireguard-tools ];
      }

      # Runs before /etc and launchd are set up, so the key exists before the
      # tunnel's job first starts.
      (lib.mkIf (!keyFromSops) {
        system.activationScripts.extraActivation.text = lib.mkAfter (
          ''
            if [ ! -s ${key} ]; then
              echo "wireguard: creating ${cfg.privateKeyFile}" >&2
              mkdir -p "$(dirname ${key})"
              chmod 0700 "$(dirname ${key})"
              (umask 077; ${wg} genkey > ${key})
            fi
          ''
          + scripts.printPublicKey
        );
      })

      # The key is in sops; root-owned and 0400 like every sops-nix secret.
      # 1600 runs after sops-nix installs the secrets (mkAfter, 1500).
      (lib.mkIf keyFromSops {
        sops.secrets."wireguard-${iface}-private-key".key = cfg.privateKeySecret;

        system.activationScripts.postActivation.text = lib.mkOrder 1600 ''
          if [ -s ${key} ]; then
            ${scripts.printPublicKey}
          else
            echo "wireguard: ${cfg.privateKeyFile} is missing or empty" >&2
          fi
        '';
      })

      (lib.mkIf hubKnown {
        # nix-darwin writes /etc/wireguard/${iface}.conf; its PostUp loads
        # the private key from privateKeyFile, so the key stays out of the
        # store. Its own launchd job is replaced below (autostart = false).
        networking.wg-quick.interfaces.${iface} = {
          autostart = false;
          address =
            let
              prefixLength = lib.last (lib.splitString "/" cfg.subnet);
            in
            [ "${cfg.address}/${prefixLength}" ];
          inherit (cfg) privateKeyFile;
          peers = [
            {
              inherit (cfg.hub) publicKey endpoint;
              allowedIPs = [ cfg.subnet ];
              inherit (cfg) persistentKeepalive;
            }
          ];
        };

        # Replaces nix-darwin's wg-quick job, which (1) lets launchd kill
        # wg-quick's helper processes (wireguard-go, the route monitor) when
        # the job stops, since it does not set AbandonProcessGroup, and (2)
        # never applies a changed config,
        # because its plist does not change and `wg-quick up` fails on an
        # interface that is already up.
        launchd.daemons."wireguard-${iface}".serviceConfig = {
          ProgramArguments = [ "${scripts.tunnelUp}" ];
          EnvironmentVariables.PATH = lib.concatStringsSep ":" [
            "${pkgs.wireguard-tools}/bin"
            "${pkgs.wireguard-go}/bin"
            config.environment.systemPath
          ];
          RunAtLoad = true;
          # Under launchd, wg-quick keeps running once the tunnel is up,
          # waiting on its route monitor. Restart it only if it fails (for
          # example, no network yet at boot).
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          AbandonProcessGroup = true;
          StandardOutPath = "/var/log/wireguard-${iface}.log";
          StandardErrorPath = "/var/log/wireguard-${iface}.log";
        };

        # Split DNS: mDNSResponder sends only names under the domain to the hub.
        environment.etc."resolver/${cfg.domain}" = lib.mkIf cfg.dns.enable {
          text = ''
            nameserver ${cfg.hub.address}
          '';
        };
      })

      # The endpoint stays out of the store: the config has no Endpoint line,
      # and PostUp sets it from the secret once the interface exists.
      (lib.mkIf (hubKnown && endpointFromSops) {
        sops.secrets."wireguard-${iface}-endpoint".key = cfg.hub.endpointSecret;

        networking.wg-quick.interfaces.${iface}.postUp =
          scripts.setEndpoint "$(cat /var/run/wireguard/${iface}.name)";
      })

      # A changed secret changes only /run/secrets, not the job's plist, so
      # activation sets it on the running tunnel itself (setting an unchanged
      # value does nothing). 1600 runs after sops-nix installs the secrets.
      (lib.mkIf (hubKnown && scripts.sopsFiles != [ ]) {
        system.activationScripts.postActivation.text = lib.mkOrder 1600 (
          ''
            if real=$(cat /var/run/wireguard/${iface}.name 2>/dev/null); then
          ''
          + lib.optionalString keyFromSops ''
            ${wg} set "$real" private-key ${key} || echo "wireguard: could not update the private key on ${iface}" >&2
          ''
          + lib.optionalString endpointFromSops ''
            ${scripts.setEndpoint "$real"} || echo "wireguard: could not update the hub endpoint on ${iface}" >&2
          ''
          + ''
            fi
          ''
        );
      })
    ]
  );
}
