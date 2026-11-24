{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.networking.wireguard;
  iface = cfg.interface;
  prefixLength = lib.last (lib.splitString "/" cfg.subnet);
  hubKnown = cfg.hub.publicKey != null && cfg.hub.endpoint != null;

  key = lib.escapeShellArg cfg.privateKeyFile;
  wg = "${pkgs.wireguard-tools}/bin/wg";

  # Brings the tunnel up from scratch. The job runs it at boot and whenever
  # activation reloads the job. Naming the config's store path makes this
  # script, and so the job's plist, change whenever the config does, and a
  # changed plist is what makes activation reload the job.
  tunnelUp = pkgs.writeShellScript "wireguard-${iface}-up" ''
    # config: ${config.environment.etc."wireguard/${iface}.conf".source}
    wg-quick down ${iface} 2>/dev/null || true
    exec wg-quick up ${iface}
  '';
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
          Until it and {option}`hub.endpoint` are set, the tunnel is not
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
    };

    persistentKeepalive = lib.mkOption {
      type = lib.types.ints.between 1 65535;
      default = 25;
      description = ''
        Seconds between keepalives to the hub. They keep this machine's NAT
        mapping open, so the hub can reach it at any time.
      '';
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wireguard/${iface}.key";
      defaultText = lib.literalExpression ''"/var/lib/wireguard/''${interface}.key"'';
      description = ''
        This machine's private key. Activation creates it with `wg genkey`
        if it does not exist and prints the public key, which goes in the
        hub's hosts table. The key never leaves the machine.
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
    lib.mkMerge [
      {
        warnings = lib.optional (!hubKnown) ''
          kaidong-desktop.networking.wireguard: hub.publicKey and hub.endpoint
          are not both set, so the tunnel is not configured yet. Activation
          still creates this machine's key and prints its public key.
        '';

        environment.systemPackages = [ pkgs.wireguard-tools ];

        # Runs before /etc and launchd are set up, so the key exists before
        # the tunnel's job first starts.
        system.activationScripts.extraActivation.text = lib.mkAfter ''
          if [ ! -s ${key} ]; then
            echo "wireguard: creating ${cfg.privateKeyFile}" >&2
            mkdir -p "$(dirname ${key})"
            chmod 0700 "$(dirname ${key})"
            (umask 077; ${wg} genkey > ${key})
          fi
          echo "wireguard: ${iface} public key: $(${wg} pubkey < ${key})" >&2
        '';
      }

      (lib.mkIf hubKnown {
        # nix-darwin writes /etc/wireguard/${iface}.conf; its PostUp loads
        # the private key from privateKeyFile, so the key stays out of the
        # store. Its own launchd job is replaced below (autostart = false).
        networking.wg-quick.interfaces.${iface} = {
          autostart = false;
          address = [ "${cfg.address}/${prefixLength}" ];
          inherit (cfg) privateKeyFile;
          peers = [
            {
              inherit (cfg.hub) publicKey endpoint;
              allowedIPs = [ cfg.subnet ];
              inherit (cfg) persistentKeepalive;
            }
          ];
        };

        # Replaces nix-darwin's wg-quick job, which (1) lets launchd kill the
        # helper processes wg-quick leaves running when it exits, since it does
        # not set AbandonProcessGroup, and (2) never applies a changed config,
        # because its plist does not change and `wg-quick up` fails on an
        # interface that is already up.
        launchd.daemons."wireguard-${iface}".serviceConfig = {
          ProgramArguments = [ "${tunnelUp}" ];
          EnvironmentVariables.PATH = lib.concatStringsSep ":" [
            "${pkgs.wireguard-tools}/bin"
            "${pkgs.wireguard-go}/bin"
            config.environment.systemPath
          ];
          RunAtLoad = true;
          # wg-quick exits once the tunnel is up; restart it only if that
          # failed (for example, no network yet at boot).
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
    ]
  );
}
