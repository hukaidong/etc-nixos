# WireGuard tunnel between the Mac Studio and the droplet

The Mac Studio and the DigitalOcean droplet (`digix`) share a private
WireGuard network with static addresses and a small DNS zone, `wg.internal`.
Two modules set it up, one per repository:

| | Hub: the droplet | Spoke: the Mac Studio |
|---|---|---|
| Repository | `nixos-lab` | `etc-nixos` |
| Module | `modules/networking/wireguard.nix` (`nixlab.networking.wireguard`) | `darwin/networking/wireguard.nix` (`kaidong-desktop.networking.wireguard`) |
| Settings | `hosts/digitalocean/default.nix` | `hosts/kaidong-mac-studio/configuration.nix` |
| Address | `10.77.0.1` (`digix.wg.internal`) | `10.77.0.2` (`mac-studio.wg.internal`) |
| Interface | `wg0`, listening on UDP 51820 | `wg0` (really `utunN`; see `/var/run/wireguard/wg0.name`) |
| Runs as | `wireguard-wg0.service`, one `wireguard-wg0-peer-*.service` per peer | launchd daemon `org.nixos.wireguard-wg0`, which runs `wg-quick up` |
| Private key | `/var/lib/wireguard/wg0.key`, made on first start | `/var/lib/wireguard/wg0.key`, made on first `darwin-rebuild switch` |
| DNS | dnsmasq on `10.77.0.1:53`, tunnel only | `/etc/resolver/wg.internal`, which sends only `*.wg.internal` to the hub |
| Logs | `journalctl -u wireguard-wg0 -u dnsmasq` | `/var/log/wireguard-wg0.log` |

Commands that change something are marked **Changes state**.

## How it fits together

- **Hub and spoke.** The droplet has a public address and the Mac is behind
  NAT, so the Mac dials the droplet and sends a keepalive every 25 seconds.
  That keeps its NAT mapping open, so the droplet can reach the Mac at any
  time without knowing its address. Spokes added later reach each other
  through the hub (the droplet forwards between tunnel peers only; its
  global `ip_forward` stays off).
- **Only the tunnel network goes through the tunnel.** The Mac routes
  `10.77.0.0/24` through it and nothing else; its internet traffic is
  unaffected.
- **The hosts table is the address book.** `nixlab.networking.wireguard.hosts`
  in nixos-lab lists every machine: name, address, public key and optional
  DNS aliases. It drives the hub's peers, the `wg.internal` zone and the
  droplet's `/etc/hosts`. A machine listed without a key is in DNS but not
  yet a peer.
- **Private keys never leave their machine.** Each machine creates its own
  key; only public keys are in the repositories.
- **Split DNS.** The Mac asks the hub only for names under `wg.internal`.
  macOS reads `/etc/resolver/<domain>`, but `dig`, `host` and `nslookup` do
  not: test with `ping`, `ssh`, `dscacheutil -q host -a name <name>` or
  `dig @10.77.0.1 <name>`.

## First-time setup

The two sides need each other's public keys, so the setup takes three
deploys.

1. **Hub.** In nixos-lab, run `deploy` (**changes state**). The droplet
   creates its key and starts `wg0` with no peers yet. Then:

   ```sh
   ssh digix sudo wg show wg0 public-key
   # The droplet's public IPv4, from DigitalOcean's metadata service:
   ssh digix curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address
   ```

   If a DigitalOcean Cloud Firewall is attached to the droplet, allow
   inbound **UDP 51820** there too; the NixOS firewall already allows it.

2. **Mac Studio.** In etc-nixos, set the hub's key and address as the
   defaults of `hub.publicKey` and `hub.endpoint` in
   `darwin/networking/wireguard.nix` (for example `"203.0.113.7:51820"`).
   Use the IP rather than a name: a `hukaidong.com` name proxied by Cloudflare
   cannot carry WireGuard's UDP, and an IP needs no DNS at boot. A DigitalOcean
   Reserved IP keeps the address if the droplet is replaced. Then
   (**changes state**):

   ```sh
   sudo darwin-rebuild switch --flake .#Kaidong-Mac-Studio
   ```

   Activation prints `wireguard: wg0 public key: ...`. Activation reprints it
   every time, and you can also read it with
   `sudo wg pubkey < /var/lib/wireguard/wg0.key`.

   Until step 2 has both values, activation warns and only creates the key.

3. **Hub again.** In nixos-lab, paste the Mac's public key into
   `hosts.mac-studio.publicKey` (and the droplet's own key into
   `hosts.digix.publicKey`, for the record), then `deploy` (**changes state**).

## Checking on it

On the Mac Studio:

```sh
sudo wg show                          # "latest handshake" under 2 minutes ago
ping -c3 10.77.0.1
ping -c3 digix.wg.internal            # through /etc/resolver
scutil --dns | grep -B1 -A3 wg.internal
tail /var/log/wireguard-wg0.log
```

On the droplet:

```sh
sudo wg show wg0                      # the Mac's endpoint is its NAT's public address
ping -c3 mac-studio.wg.internal
```

After the droplet reboots or restarts `wg0`, it cannot reach the Mac for up
to about two minutes: the Mac's keepalives belong to the old session, and
keepalives never start a new handshake. The Mac starts one when its session
is two minutes old, or at once when it sends anything to the droplet (a
`ping 10.77.0.1` on the Mac reconnects it immediately). The VM test measured
84 seconds.

`ssh mac-studio.wg.internal` from the droplet also needs Remote Login turned
on in the Mac's System Settings. If ping from the droplet times out while
the Mac can ping the droplet, check that the macOS firewall's stealth mode
is off.

## Operating it

- **Restart the tunnel on the Mac** (**changes state**):
  `sudo launchctl kickstart -k system/org.nixos.wireguard-wg0`. The job takes
  `wg0` down and brings it up again from `/etc/wireguard/wg0.conf`.
- **Config changes apply on switch.** When `darwin-rebuild switch` changes
  the tunnel's config, the job's plist changes too, so activation reloads the
  job and the tunnel comes back up with the new config. Connections over the
  tunnel drop for a moment.
- **Add a machine.** Give it the next free address in the hosts table in
  nixos-lab, with `publicKey = null`. Configure it as a spoke with that
  address (a NixOS machine can mirror the darwin module with
  `networking.wg-quick.interfaces`), switch it to create its key, then put
  the key in the table and `deploy`.
- **Add a DNS name for a service on a machine**: add it to that machine's
  `aliases` in the hosts table and `deploy`; `grafana` on `digix` becomes
  `grafana.wg.internal`.

## Design notes

**Why the module runs its own launchd job.** nix-darwin's
`networking.wg-quick` writes `/etc/wireguard/wg0.conf` and a launchd job that
runs `wg-quick up`. Its config generation is used as-is, but its job is
replaced (`autostart = false`), for two reasons:

- `wg-quick` on macOS starts helper processes and exits. Without
  `AbandonProcessGroup`, launchd kills what the job leaves behind when it
  exits ([wireguard list, 2018](https://lists.zx2c4.com/pipermail/wireguard/2018-July/003168.html)).
- Its plist never changes with the config, and `wg-quick up` fails on an
  interface that is already up, so a changed config would wait for a reboot.
  This job's script names the config's store path, so a new config means a
  new plist, which makes activation reload the job; the job takes the tunnel
  down before bringing it up.

**Why the keys are not in sops.** A key made on the machine never exists
anywhere else, not even encrypted in a repository, and it is on disk before
the tunnel's job first starts. A sops secret is decrypted by a separate
launchd job at boot, which the tunnel would have to wait for (and see the
sops-install-secrets race in [GitHub-Runners.md](GitHub-Runners.md)). The
catch is on the droplet: if it is rebuilt from an image, it makes a new key,
and every spoke needs the new public key. To avoid that, keep the droplet's
key in nixos-lab's sops file and point `privateKeyFile` at the secret.

**Why not a mesh VPN.** Tailscale with Headscale, NetBird, Nebula and
ZeroTier add NAT traversal between spokes, client apps and access control,
but each runs a control plane or certificate authority. For a fixed set of
machines with one public server, plain WireGuard is a kernel interface on
the droplet and one `wg-quick` job on the Mac, both declared in Nix. Spoke
traffic going through the droplet is the cost. If direct spoke-to-spoke
connections or phones join later, Headscale on the droplet is the natural
next step.
