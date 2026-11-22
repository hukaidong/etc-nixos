# GitHub runners on the Mac Studio

The Mac Studio runs the kd-lapwings organization's two self-hosted runners,
each in a VM on the RunnerVMs SSD. `darwinConfigurations.Kaidong-Mac-Studio`
sets them up: `darwin/services/github-runner*.nix`, the scripts in
`configs/github-runner-linux/`, `configs/github-runner-macos-vm/` and
`configs/github-runners/`, and the settings in
`hosts/kaidong-mac-studio/configuration.nix`. Pull requests #3, #5 and #4
explain the design and the one-time setup. This page covers checking on the
runners and keeping them running.

Run the commands on the Mac Studio as your own user. They use `sudo` where
they need it. Commands that change something are marked **Changes state**,
and commands that delete data are marked **Destructive**.

## Overview

| | Linux runner | macOS runner |
|---|---|---|
| Name on GitHub | `Kaidong-Mac-Studio-linux` | `Kaidong-Mac-Studio-darwin` |
| Labels | `self-hosted`, `Linux`, `ARM64` | `self-hosted`, `macOS`, `ARM64` |
| Runs in | A Colima VM (`vz`). Each job runs in a fresh Docker container, with an ephemeral runner registered for that one job | The Tart VM `runner` (macOS 27.2), with a persistent runner |
| Host daemons | `org.nixos.github-runner-linux-vm` (the VM) and `org.nixos.github-runner-linux` (the launcher) | `org.nixos.github-runner-macos-vm` (the VM) and `org.nixos.github-runner-macos-vm-provision` (the provisioner) |
| Host user (uid/gid) | `_github-runner-linux` (540) | `_github-runner-macos` (541) |
| State | `/Volumes/RunnerVMs/Kaidong-Mac-Studio-linux`, which is also `COLIMA_HOME` and the user's home | `/Volumes/RunnerVMs/Kaidong-Mac-Studio-darwin-vm`: `tart/` is `TART_HOME`; `ssh/` holds the provisioning key, its ssh `config` and the pinned guest host key (`known_hosts`) |
| Host logs | `/var/log/github-runners/Kaidong-Mac-Studio-linux/vm.log` and `runner.log` | `/var/log/github-runners/Kaidong-Mac-Studio-darwin-vm/vm.log` and `provision.log` |
| Size | 6 CPUs, 10 GiB memory, 100 GiB disk | 6 CPUs, 10 GiB memory, 150 GB disk |
| Inside | Jobs run as `runner` (uid 1001), with no sudo. The Nix store, rustup and cargo live in cache volumes | The runner is the launchd daemon `org.nixos.github-runner-darwin`, running as `_github-runner`. Its state is in `/var/lib/github-runners/Kaidong-Mac-Studio-darwin`, its logs in `/var/log/github-runners/Kaidong-Mac-Studio-darwin/launchd-stdout.log` and `launchd-stderr.log` |

**The token.** Both runners use one fine-grained personal access token,
`github-runner-token` in `secrets/secrets.yaml`. At boot, sops-nix decrypts a
copy for each host user: `/run/secrets/github-runner-token-linux` and
`/run/secrets/github-runner-token-macos`, mode 0400. The token never leaves
the host: the VMs only ever get short-lived registration tokens.

**The SSD.** `/Volumes/RunnerVMs` is an external APFS volume with ownership
enabled.
- Activation sets `AutomountDisksWithoutUserLogin`, so the volume mounts at
  boot without a login.
- Activation creates the state directories only while the volume is really
  mounted.
- Every daemon first runs `github-runners-state-dir <state dir>`. It waits up
  to 2 minutes for the volume and the directory, then exits 1, and launchd
  tries again. See [The SSD is not mounted](#the-ssd-is-not-mounted).

## Helpers

Paste these into a zsh or bash shell on the Mac Studio. They read the
installed plists and the daemons' scripts, so they follow whatever system is
active without hard-coding store paths. `tart` and `colima` are not on your
PATH; they are only in the daemons' closures.

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

# Run a command as _github-runner-macos with the provisioner's PATH (tart,
# ssh, nix) and TART_HOME.
as_macos() {
  local script
  script=$(daemon_script github-runner-macos-vm-provision)
  (cd / && sudo -u _github-runner-macos env -i \
    PATH="$(sed -n 's/^export PATH="\(.*\):\$PATH"$/\1/p' "$script"):/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$(plist_env github-runner-macos-vm-provision HOME)" \
    TART_HOME="$(sed -n 's/^default TART_HOME //p' "$script")" \
    "$@")
}

# The provisioner's ssh config: its key, user admin, the pinned host key.
macos_ssh=/Volumes/RunnerVMs/Kaidong-Mac-Studio-darwin-vm/ssh/config

# Run a command in the macOS VM as admin, who has passwordless sudo there.
# With no command, it opens a shell.
in_vm() {
  as_macos ssh -F "$macos_ssh" "$(as_macos tart ip runner)" "$@"
}
```

## Health check

These commands only read.

The daemons:

```sh
for label in github-runner-linux-vm github-runner-linux github-runner-macos-vm github-runner-macos-vm-provision; do
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
sudo tail -n 50 /var/log/github-runners/Kaidong-Mac-Studio-linux/vm.log /var/log/github-runners/Kaidong-Mac-Studio-linux/runner.log
sudo tail -n 50 /var/log/github-runners/Kaidong-Mac-Studio-darwin-vm/vm.log /var/log/github-runners/Kaidong-Mac-Studio-darwin-vm/provision.log
```

- **`runner.log`:** shows the runner's console. When idle it ends with
  `Listening for Jobs`, and during a job it shows the job's start and end.
- **`provision.log`:** quiet unless the provisioner changed something or
  failed.

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
sed -n 's/^IMAGE_TAG=//p' "$(sed -n 's/^exec //p' "$(daemon_script github-runner-linux)")"
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
image's store. When the launcher loads a new image, it deletes the volumes of
other tags. Set `linux.cacheVolumes = false` to run every job without them.

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

## macOS runner (Tart)

**The VM daemon** runs `configs/github-runner-macos-vm/vm.sh`:
- **First start:** clones the VM `runner` from the pinned image if it is
  missing, which downloads about 30 GB.
- **Every start:** applies the CPUs, memory and disk size, then runs the VM
  headless.
- **Stop:** shuts macOS down over SSH, and powers off only what is still
  running after 40 s.

**The provisioner** runs `configs/github-runner-macos-vm/provision.sh` and its
guest half, `guest.sh`. It brings the guest up to date at start and every 5
minutes, over SSH. In order, it handles:
1. Its key, and the guest's hardening.
2. The disk growth.
3. The Command Line Tools and Nix.
4. The guest's nix-darwin system, `Kaidong-Mac-Studio-runner-vm`.
5. The runner's registration.

It logs only what it changes.

### Look around

These commands only read:

```sh
as_macos tart list
as_macos tart get runner
as_macos tart ip runner
```

A shell in the VM, as `admin`:

```sh
in_vm
```

Admin accepts only the provisioner's key, and the provisioner's ssh config
pins the guest's host key as `runner`. Password logins are off.

The guest's runner:

```sh
in_vm 'sudo launchctl print system/org.nixos.github-runner-darwin | grep -E "^\s(state|runs|pid|last exit code) ="'
in_vm 'sudo tail -n 50 /var/log/github-runners/Kaidong-Mac-Studio-darwin/launchd-stdout.log /var/log/github-runners/Kaidong-Mac-Studio-darwin/launchd-stderr.log'
in_vm 'sudo test -f /var/lib/github-runners/Kaidong-Mac-Studio-darwin/.runner && echo registered'
```

Check that the guest runs the system the host built for it. These two should
print the same path:

```sh
in_vm 'readlink /run/current-system'
sed -n 's/^default GUEST_SYSTEM //p' "$(daemon_script github-runner-macos-vm-provision)"
```

Each switch from a new commit changes the guest system: it records the
configuration revision. The provisioner deploys it within seconds.

### Provision by hand

To make one provisioning pass by hand (**Changes state**, the same as the
daemon), stop the daemon first so the two don't run at once:

```sh
sudo launchctl bootout system/org.nixos.github-runner-macos-vm-provision
as_macos "$(daemon_script github-runner-macos-vm-provision)" --once
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-macos-vm-provision.plist
```

The script's inputs are defaults, and the environment overrides them (see the
header of `provision.sh`). `as_macos` passes only `PATH`, `HOME` and
`TART_HOME`, so everything else comes from the active system. To test against
another VM, override `VM_NAME`, `TART_HOME`, `STATE_DIR` and `KEY_DIR`, for
example `as_macos env VM_NAME=test … "$(daemon_script …)" --once`. With
`REGISTRATION_TOKEN_FILE` set to a file holding a token, it uses that token
instead of asking GitHub.

### Re-register the runner

Re-register if GitHub removed the runner (for example after 14 days offline),
or if it stays offline while the VM is fine. **Changes state.**

```sh
in_vm 'sudo rm -f /var/lib/github-runners/Kaidong-Mac-Studio-darwin/.runner && sudo launchctl kill TERM system/org.nixos.github-runner-darwin'
sudo launchctl kickstart -k system/org.nixos.github-runner-macos-vm-provision
```

What happens next:
1. The runner restarts and finds no `.runner`. It then waits for a token: its
   service watches the token file.
2. The provisioner's next pass, which the `kickstart` starts right away, mints
   a registration token and writes it to
   `/var/lib/github-runners/registration-token` in the guest.
3. The runner registers with `--replace`, taking over its old registration.
4. The provisioner deletes the token once the runner is registered, or after
   3 minutes.

### The guest's host key

The provisioner pins the guest's SSH host key on first contact with a new VM.
If `provision.log` says it cannot log in and to delete `known_hosts`, the key
changed. Only if you replaced the VM on purpose, delete the pinned key; the
next pass pins the new one:

```sh
as_macos rm -f /Volumes/RunnerVMs/Kaidong-Mac-Studio-darwin-vm/ssh/known_hosts
```

### Start over from a fresh VM

**Destructive**: the VM and everything in it. The downloaded image stays in
`tart/`.

```sh
sudo launchctl bootout system/org.nixos.github-runner-macos-vm-provision
sudo launchctl bootout system/org.nixos.github-runner-macos-vm     # shuts macOS down, up to 75 s
as_macos tart delete runner
as_macos rm -f /Volumes/RunnerVMs/Kaidong-Mac-Studio-darwin-vm/ssh/known_hosts
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-macos-vm.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-macos-vm-provision.plist
```

- **The new VM:** the VM daemon clones it from the cached image (from the
  network if the cache is gone), and the provisioner sets it up from scratch:
  hardening, the Command Line Tools, Nix, the guest system and registration.
- **The registration:** the new runner takes over the old one.
- **New image:** after changing `darwinVM.image`, do the same; an existing VM
  keeps the image it was cloned from.

### Disk, CPUs and memory

- **Disk:** `darwinVM.disk` only grows. On the next VM start, `vm.sh` grows
  the disk image, and macOS fills the new space when it boots. The
  provisioner's disk check grows the boot container if macOS didn't, and only
  warns if it can't. To see the result: `in_vm 'df -h /'`.
- **CPUs and memory:** they change at the next VM start, which any switch that
  changes them triggers. That restart reboots the guest.

## Day-2 operations

### Stop, start and restart daemons

Restart a daemon (**Changes state**; restarting a VM or the Linux launcher
kills a job running there):

```sh
sudo launchctl kickstart -k system/org.nixos.github-runner-linux     # or another label
```

`kickstart` waits while launchd throttles a job that exited in the last 30 to
60 s, so if it seems to hang, that is why.

Stop a daemon, then start it again:

```sh
sudo launchctl bootout system/org.nixos.github-runner-linux
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.github-runner-linux.plist
```

- **Order:** stop the launcher before the Linux VM, and the provisioner before
  the macOS VM; start them in the reverse order.
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
- **The macOS guest:** the switch restarts the provisioner, which deploys the
  new guest system. The guest's runner restarts only if its own service
  changed, for example for a new runner version.
- **Tart, Colima or the VM scripts:** a change to any of them restarts that
  VM's daemon, which shuts down and reboots the VM.
- **The runner version:** both runners come from nixpkgs' `github-runner` and
  never update themselves (`--disableupdate`). GitHub stops sending jobs to a
  runner that falls too far behind the current release, so update
  `flake.lock` regularly.

### The SSD is not mounted

Symptoms:
- **Daemon logs:** `/Volumes/RunnerVMs is not mounted; not starting`, every
  few minutes.
- **launchctl:** the daemons' `runs` keeps climbing, with `last exit code`
  1.
- **GitHub:** both runners are offline.
- **darwin-rebuild:** activation prints a red warning about the volume.

Check, then mount it (the mount is **Changes state**):

```sh
diskutil info /Volumes/RunnerVMs | grep -E 'Mounted|Owners'
diskutil list external
diskutil mount RunnerVMs
```

The daemons start on their own within a few minutes, or right away with
`kickstart -k`.

- **"does not exist; activate the system again":** the volume wasn't mounted
  at the last activation, so the state directory was never made. Run
  `sudo darwin-rebuild switch --flake .#Kaidong-Mac-Studio`.
- **Never create directories under `/Volumes/RunnerVMs` while the volume is
  unmounted.** They would land on the internal disk, under the stale mount
  point.
- **A stray `/Volumes/RunnerVMs`:** if a non-empty one exists while the volume
  is unmounted, macOS may mount the volume elsewhere, for example
  `/Volumes/RunnerVMs 1`. Look at what is in the stray directory before you
  move it aside.

### Reboot

FileVault is on. A plain restart stops at the login window until someone
unlocks the disk, and the runners stay down until then. To restart unattended:

```sh
sudo fdesetup authrestart
```

This unlocks the disk once at the next boot. The SSD mounts at boot, and the
daemons start without a login. Afterwards, run the [health check](#health-check).

## Migrating from the layout before #4

Before #4, the macOS runner ran natively on the host, and the Linux runner
kept its state in `/var/lib/github-runners/Kaidong-Mac-Studio-linux`. #4's
description has the one-time steps for switching over: moving
`_github-runner-linux`'s home to the SSD before the first switch, and cleaning
up what the old layout leaves on the internal disk.
