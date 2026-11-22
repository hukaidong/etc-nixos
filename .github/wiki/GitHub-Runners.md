# GitHub runners on the Mac Studio

The Mac Studio runs the kd-lapwings organization's two self-hosted runners.
`darwinConfigurations.Kaidong-Mac-Studio` sets them up:
`darwin/services/github-runners.nix` (shared options and the macOS runner),
`darwin/services/github-runner-linux.nix` with the scripts in
`configs/github-runner-linux/`, and the settings in
`hosts/kaidong-mac-studio/configuration.nix`. Pull requests #3 and #5 explain
the design and the one-time setup. This page covers checking on the runners
and keeping them running.

Run the commands on the Mac Studio as your own user. They use `sudo` where
they need it. Commands that change something are marked **Changes state**,
and commands that delete data are marked **Destructive**.

## Overview

| | macOS runner | Linux runner |
|---|---|---|
| Name on GitHub | `Kaidong-Mac-Studio-darwin` | `Kaidong-Mac-Studio-linux` |
| Labels | `self-hosted`, `macOS`, `ARM64` | `self-hosted`, `Linux`, `ARM64` |
| Runs | Natively on the host, a persistent runner (nix-darwin's `services.github-runners`) | In a Colima VM (`vz`). Each job runs in a fresh Docker container, with an ephemeral runner registered for that one job |
| Daemons | `org.nixos.github-runner-darwin` | `org.nixos.github-runner-linux-vm` (the VM) and `org.nixos.github-runner-linux` (the launcher) |
| Host user (uid) | `_github-runner` (533), home `/var/lib/github-runners` | `_github-runner-linux` (540), home = state directory |
| State | `/var/lib/github-runners/Kaidong-Mac-Studio-darwin` (`RUNNER_ROOT`, and `HOME` for jobs) | `/var/lib/github-runners/Kaidong-Mac-Studio-linux`, which is also `COLIMA_HOME` |
| Work tree | `/var/lib/github-runners/_work/Kaidong-Mac-Studio-darwin`, emptied every time the daemon starts | Inside the job's container, gone after the job |
| Logs | `/var/log/github-runners/Kaidong-Mac-Studio-darwin/launchd-stdout.log` and `launchd-stderr.log` | `/var/log/github-runners/Kaidong-Mac-Studio-linux/vm.log` and `runner.log` |
| Jobs run as | `_github-runner`, on the host | `runner` (uid 1001) in the container, with no sudo |
| Size | The host | 6 CPUs, 12 GiB memory, 100 GiB disk |

**The token.** Both runners use one fine-grained personal access token,
`github-runner-token` in `secrets/secrets.yaml`. At boot, sops-nix decrypts a
copy for each host user, mode 0400:
- `/run/secrets/github-runner-token-darwin`, owned by `_github-runner`. The
  macOS runner registers itself with it. Its jobs run as the same user, so
  **a macOS job can read the token** (#3's known caveat).
- `/run/secrets/github-runner-token-linux`, owned by `_github-runner-linux`.
  The launcher uses it to get a short-lived registration token per job; the
  container never sees the token itself.

## Helpers

Paste these into a zsh or bash shell on the Mac Studio. They read the
installed plists, so they follow whatever system is active without
hard-coding store paths. `colima` and `docker` are not on your PATH; they are
only in the daemons' closures.

```sh
# The value of an environment variable in a daemon's plist.
plist_env() {
  plutil -extract "EnvironmentVariables.$2" raw -o - "/Library/LaunchDaemons/org.nixos.$1.plist"
}

# The script a daemon runs: the last word of its command line.
daemon_script() {
  local cmd
  cmd=$(plutil -extract ProgramArguments.2 raw -o - "/Library/LaunchDaemons/org.nixos.$1.plist")
  printf '%s\n' "${cmd##* }"
}

# Run a command as _github-runner-linux with the Linux daemons' environment
# (colima, docker and ssh on PATH, COLIMA_HOME, DOCKER_HOST).
as_linux() {
  (cd / && sudo -u _github-runner-linux env -i \
    PATH="$(plist_env github-runner-linux-vm PATH)" \
    HOME="$(plist_env github-runner-linux-vm HOME)" \
    COLIMA_HOME="$(plist_env github-runner-linux-vm COLIMA_HOME)" \
    DOCKER_CONFIG="$(plist_env github-runner-linux-vm DOCKER_CONFIG)" \
    DOCKER_HOST="$(plist_env github-runner-linux DOCKER_HOST)" \
    "$@")
}

# Run a command as _github-runner with the macOS runner's environment, which
# is what its jobs get (PATH, HOME, RUNNER_ROOT).
as_darwin() {
  (cd / && sudo -u _github-runner env -i \
    PATH="$(plist_env github-runner-darwin PATH)" \
    HOME="$(plist_env github-runner-darwin HOME)" \
    RUNNER_ROOT="$(plist_env github-runner-darwin RUNNER_ROOT)" \
    "$@")
}
```

## Health check

These commands only read.

The daemons:

```sh
for label in github-runner-darwin github-runner-linux-vm github-runner-linux; do
  echo "== $label"
  launchctl print "system/org.nixos.$label" | grep -E '^\s(state|runs|pid|last exit code) ='
done
```

A healthy daemon is `running`, and its `runs` count stays put.
- **Linux launcher:** `runs` goes up by one per job. That's normal: it exits
  after each job, and launchd starts it again.
- **Crash loop:** if any other daemon's `runs` keeps climbing, with a nonzero
  `last exit code`, it is crashing. Read its log.

The logs:

```sh
sudo tail -n 50 /var/log/github-runners/Kaidong-Mac-Studio-darwin/launchd-stdout.log /var/log/github-runners/Kaidong-Mac-Studio-darwin/launchd-stderr.log
sudo tail -n 50 /var/log/github-runners/Kaidong-Mac-Studio-linux/vm.log /var/log/github-runners/Kaidong-Mac-Studio-linux/runner.log
```

Both runners' console logs end with `Listening for Jobs` when idle, and show
each job's start and end.

GitHub's view of the runners. The token is read as root into a request
header, so it is never on a command line or in the output:

```sh
sudo bash -c 'curl --silent --show-error \
    --header @<(printf "Authorization: Bearer %s\n" "$(</run/secrets/github-runner-token-linux)") \
    --header "Accept: application/vnd.github+json" \
    https://api.github.com/orgs/kd-lapwings/actions/runners' |
  jq -r '.message // empty, (.runners[]? | [.name, .os, .status, (if .busy then "busy" else "idle" end), ([.labels[].name] | join(","))] | @tsv)'
```

Both runners should be `online`. After each job, the Linux runner is offline
for a few seconds while the launcher registers the next one under the same
name.

## macOS runner (native)

The daemon runs nix-darwin's start script, `github-runner-darwin-start`. Every
time it starts, it:
1. Empties the work tree, `/var/lib/github-runners/_work/Kaidong-Mac-Studio-darwin`.
2. Registers the runner if `.runner` is missing from the state directory:
   `config.sh --unattended --disableupdate --replace --pat <token>`.
3. Runs `Runner.Listener` until it exits; launchd starts it again
   (`KeepAlive`, which `github-runners.nix` forces on).

### Look around

These commands only read:

```sh
sudo ls -la /var/lib/github-runners/Kaidong-Mac-Studio-darwin
sudo test -f /var/lib/github-runners/Kaidong-Mac-Studio-darwin/.runner && echo registered
sudo find /var/lib/github-runners/Kaidong-Mac-Studio-darwin -path '*_diag*' -name '*.log' -mtime -1
```

The last command lists the runner's own diagnostic logs (`Runner_*.log`,
`Worker_*.log`) from the last day, if any.

What a job sees. Jobs get the daemon's `PATH`: bash, coreutils, git, gnutar,
gzip, Nix and rustup from the Nix store, then `/usr/bin`, `/bin`, `/usr/sbin`
and `/sbin` (make, clang and the rest of the Xcode Command Line Tools).
Homebrew is not on it. To add packages, set
`kaidong-desktop.services.githubRunners.darwin.extraPackages`.

```sh
as_darwin sh -c 'echo "$PATH" | tr : "\n"'
as_darwin sh -c 'command -v make clang git nix rustup'
as_darwin rustup show
```

`HOME` is the state directory, so rustup's toolchains (`~/.rustup`) and
cargo's registry (`~/.cargo`) stay there across jobs and restarts.

### Restart the runner

**Changes state**; kills a running macOS job:

```sh
sudo launchctl kickstart -k system/org.nixos.github-runner-darwin
```

The restart also empties the work tree.

### Re-register the runner

Re-register if GitHub removed the runner (for example after 14 days offline),
or if the console log shows it cannot authenticate. **Changes state.**

```sh
sudo rm -f /var/lib/github-runners/Kaidong-Mac-Studio-darwin/.runner \
  /var/lib/github-runners/Kaidong-Mac-Studio-darwin/.credentials \
  /var/lib/github-runners/Kaidong-Mac-Studio-darwin/.credentials_rsaparams
sudo launchctl kickstart -k system/org.nixos.github-runner-darwin
```

The start script finds no `.runner` and registers again with the token. The
registration uses `--replace`, so it takes over the old one of the same name.

### The token

The token file is readable by the macOS runner's jobs. If a job may have
leaked it, revoke it on GitHub, put a new one in `secrets/secrets.yaml`
(`sops secrets/secrets.yaml`), commit, and switch. The macOS runner keeps its
registration (it authenticates with its own credentials once registered); the
Linux launcher reads the new token for its next job.

## Linux runner (Colima)

**The VM daemon** runs `colima start default --foreground`, with the state
directory as `COLIMA_HOME`; Lima's files are in its `_lima/`.

**The launcher**, for each job:
1. Loads the runner image into the VM's Docker if the image's tag is missing.
2. Gets a registration token from GitHub.
3. Runs one container, named `Kaidong-Mac-Studio-linux`, for one job, then
   exits; launchd starts it again for the next job.

### Look around

These commands only read:

```sh
as_linux colima status --extended
as_linux docker ps --all
as_linux docker image ls github-runner-linux
as_linux docker volume ls --filter label=org.nixos.github-runner-linux=Kaidong-Mac-Studio-linux
as_linux docker system df
as_linux docker logs --tail 50 Kaidong-Mac-Studio-linux
```

The image tag the active system expects (the launcher loads it when it is
missing):

```sh
sed -n 's/^IMAGE_TAG=//p' "$(daemon_script github-runner-linux)"
```

A shell in the VM (where Docker runs), or in the job container:

```sh
as_linux colima ssh
as_linux docker exec -it Kaidong-Mac-Studio-linux bash          # as runner, like the jobs
as_linux docker exec -it -u 0 Kaidong-Mac-Studio-linux bash     # as root, for debugging only
```

A shell in the container shares it with the job running there. The runner's
own diagnostic logs stay inside the container, under `/runner`.

### Cache volumes

The cache volumes belong to the image tag. Each tag has three:

| Volume | Mounted at |
|---|---|
| `Kaidong-Mac-Studio-linux-nix-<tag>` | `/nix` |
| `Kaidong-Mac-Studio-linux-rustup-<tag>` | `/home/runner/.rustup` |
| `Kaidong-Mac-Studio-linux-cargo-<tag>` | `/home/runner/.cargo` |

Docker fills a new volume from the image, so the `/nix` volume starts with the
image's store and every volume belongs to `runner`. When the launcher loads a
new image, it deletes the volumes of other tags. Set `linux.cacheVolumes =
false` to run every job without them.

To reset the caches (**Destructive**: the next job downloads its toolchains
again; stopping the launcher kills a running job):

```sh
sudo launchctl bootout system/org.nixos.github-runner-linux
as_linux docker rm --force Kaidong-Mac-Studio-linux
as_linux sh -c 'docker volume ls --quiet --filter label=org.nixos.github-runner-linux=Kaidong-Mac-Studio-linux | xargs docker volume rm'
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-linux.plist
```

### Reload the image

Reload the image if the copy in the VM is damaged (**Changes state**; kills a
running job):

```sh
sudo launchctl bootout system/org.nixos.github-runner-linux
as_linux sh -c 'docker rm --force Kaidong-Mac-Studio-linux; docker image ls --quiet github-runner-linux | xargs docker image rm --force'
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-linux.plist
```

The launcher logs `loading github-runner-linux:<tag>`. It streams the image
from the Nix store again, which takes a few minutes. The cache volumes of the
same tag stay.

### Recreate the VM

**Destructive**: the VM, its Docker images and the cache volumes.

```sh
sudo launchctl bootout system/org.nixos.github-runner-linux
sudo launchctl bootout system/org.nixos.github-runner-linux-vm     # Colima stops the VM, up to 60 s
as_linux colima delete --force --data
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-linux-vm.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-linux.plist
```

- **`--data`:** without it, `colima delete` keeps Docker's data disk.
- **Next start:** Colima sets up a new VM, and the launcher loads the runner
  image into it.
- **When to recreate:** after changing `linux.vmType`. A VM keeps its type
  until it is recreated.
- **Size changes:** CPUs and memory change when the VM daemon restarts, which
  any switch that changes them does. `linux.disk` only grows.

## Day-2 operations

### Stop, start and restart daemons

Restart a daemon (**Changes state**; restarting the macOS runner, the Linux VM
or the Linux launcher kills a job running there):

```sh
sudo launchctl kickstart -k system/org.nixos.github-runner-linux     # or another label
```

`kickstart` waits while launchd throttles a job that exited in the last 30 s,
so if it seems to hang, that is why.

Stop a daemon, then start it again:

```sh
sudo launchctl bootout system/org.nixos.github-runner-linux
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-linux.plist
```

- **Order:** stop the Linux launcher before the Linux VM; start them in the
  reverse order.
- **Booted-out daemons stay stopped** until you bootstrap them or the Mac
  restarts. `darwin-rebuild switch` only reloads daemons whose plist changed.

### Update flake.lock

What updating `flake.lock` and switching does:
- **The Linux image:** when any package in it changes, so does its tag. The
  switch restarts the launcher, which kills a running job. The launcher then
  loads the new image and deletes the old image and the old tag's cache
  volumes, so the first jobs afterwards are slower. `darwin-rebuild`
  downloads the changed Linux store paths before the switch; the whole image
  is about 1.2 GiB.
- **The macOS runner:** the switch restarts it if its service changed, for
  example for a new runner version or a changed PATH. That kills a running
  job and empties the work tree.
- **Colima or the VM settings:** a change restarts the VM daemon, which shuts
  down and boots the VM again.
- **The runner version:** both runners come from nixpkgs' `github-runner` and
  never update themselves (`--disableupdate`). GitHub stops sending jobs to a
  runner that falls too far behind the current release, so update
  `flake.lock` regularly.

### Reboot

FileVault is on. A plain restart stops at the login window until someone
unlocks the disk, and the runners stay down until then. To restart unattended:

```sh
sudo fdesetup authrestart
```

This unlocks the disk once at the next boot, and the daemons start without a
login. Afterwards, run the [health check](#health-check).

## Known nix-darwin switch pitfalls

Seen on this machine while moving between #3/#5 and #4 and back:

1. **Removed daemons can survive a switch.** When a switch changes
   `org.nixos.activate-system`'s plist, nix-darwin's launchd step reloads it
   first (it sorts first), and its `RunAtLoad` immediately points
   `/run/current-system` at the new system. The removal loop then compares the
   new system with itself and removes nothing. Seen twice: the macOS runner
   stayed loaded after the switch to #4, and #4's VM daemons stayed after the
   switch back. After a switch that drops daemons, check and remove by hand
   (**Changes state**):

   ```sh
   ls /Library/LaunchDaemons | grep org.nixos
   label=org.nixos.github-runner-macos-vm     # a daemon the new system no longer has
   sudo launchctl bootout "system/$label"
   sudo rm "/Library/LaunchDaemons/$label.plist"
   ```

2. **sops-install-secrets race.** On a switch that changes which secrets
   exist, nix-darwin reloads `org.nixos.sops-install-secrets` (`RunAtLoad`)
   while the activation runs its own `sops-install-secrets`. One fails with
   `cannot write /run/secrets.d/<n>/<secret>: open ...: no such file or
   directory`, and the activation stops after that step. The other one has
   usually installed the secrets. Run the same switch again: nothing is
   reloaded the second time, so it completes.

3. **nix-darwin won't move an existing user's home.** If the configured home
   of a user it manages changes, activation stops with `config contains the
   wrong home directory for <user>, aborting activation`. Move the home once
   by hand before the switch:

   ```sh
   user=_github-runner-linux home=/var/lib/github-runners/Kaidong-Mac-Studio-linux   # the configured home
   sudo dscl . -create "/Users/$user" NFSHomeDirectory "$home"
   ```

   #4 did this for `_github-runner-linux` (to the SSD), and the rollback to
   this layout moved it back (the example above).

4. **TCC and the external SSD.** A launchd daemon may use an external volume
   only inside its user's home; elsewhere on it, files fail with `Operation
   not permitted` (TCC "Removable Volumes" denies platform binaries without
   asking). launchd also refuses to open a daemon's `StandardOutPath` or
   `WorkingDirectory` on the external volume: the job exits 78 with `Unable to
   open stdout path ... Operation not permitted`. Keep logs on the internal
   disk, and state inside the user's home.

## Leftovers from the #4 attempt

PR #4 (the macOS runner in a Tart VM, state on the RunnerVMs SSD) was rolled
back. These stay on purpose, so #4 can reuse them, and nothing in this layout
uses them:
- the user `_github-runner-macos` (541), home
  `/Volumes/RunnerVMs/Kaidong-Mac-Studio-darwin-vm`;
- `/Volumes/RunnerVMs/Kaidong-Mac-Studio-darwin-vm` (a Tart VM that never
  booted) and `/Volumes/RunnerVMs/Kaidong-Mac-Studio-linux` (#4's Colima VM);
- `/var/log/github-runners/Kaidong-Mac-Studio-darwin-vm`;
- `AutomountDisksWithoutUserLogin = 1` in
  `/Library/Preferences/SystemConfiguration/autodiskmount`.
