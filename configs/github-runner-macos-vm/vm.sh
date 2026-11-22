# VM daemon of the macOS GitHub Actions runner on the Mac Studio: a Tart VM
# that runs the runner, so jobs never run on the host itself.
# darwin/services/github-runner-macos-vm.nix puts the defaults of the inputs
# below in front of this file, wraps it with writeShellApplication (strict
# mode, PATH) and runs it as a launchd daemon (KeepAlive) as the hidden
# _github-runner-macos user.
#
# Creates the VM from the pinned image the first time (a download of about
# 30 GB), applies the configured CPUs, memory and disk size, and runs it
# headless until it stops; launchd then starts it again. provision.sh sets up
# the guest over SSH.
#
# Inputs (environment): STATE_DIR (on an external volume, it must be mounted),
# TART_HOME, VM_NAME, IMAGE, CPUS, MEMORY_MIB, DISK_GB, KEY_DIR (provision.sh's
# SSH key and config, used to shut the guest down cleanly); HOME, where the
# user's login keychain is (created if missing).

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

github-runners-state-dir "$STATE_DIR"
cd "$STATE_DIR"
export TART_HOME
# Tart would otherwise delete cached images when the disk runs low; the cached
# image is what a replacement VM is cloned from.
export TART_NO_AUTO_PRUNE=1
mkdir -p "$TART_HOME"

if ! tart get "$VM_NAME" >/dev/null 2>&1; then
  log "creating $VM_NAME from $IMAGE (the first time, this downloads about 30 GB)"
  tart clone "$IMAGE" "$VM_NAME"
fi

vm_config=$(tart get "$VM_NAME" --format json)
if [[ $(jq -r .CPU <<<"$vm_config") != "$CPUS" ||
  $(jq -r .Memory <<<"$vm_config") != "$MEMORY_MIB" ]]; then
  log "giving $VM_NAME $CPUS CPUs and $MEMORY_MIB MiB of memory"
  tart set "$VM_NAME" --cpu "$CPUS" --memory "$MEMORY_MIB"
fi
# Disks only grow. The guest's boot container takes up the new space when it
# boots; provision.sh checks that it did.
if (($(jq -r .Disk <<<"$vm_config") < DISK_GB)); then
  log "growing the disk of $VM_NAME to $DISK_GB GB"
  tart set "$VM_NAME" --disk-size "$DISK_GB"
fi

# Since macOS 15, Virtualization.framework keeps a VM's host key in the login
# keychain and starts no VM without one, unlocked (Tart's FAQ, "Running Tart
# headless"); `tart run` would fail with "The virtual machine encountered a
# security error ... Failed to create new HostKey". This daemon's user never
# logs in, so it gets a login keychain in its home with an empty password,
# which guards nothing that the home, private to this user, does not.
if [[ ! -e $HOME/Library/Keychains/login.keychain-db ]]; then
  log "creating a login keychain for $(id -un) in $HOME"
  /usr/bin/security create-keychain -p '' login.keychain
fi
/usr/bin/security unlock-keychain -p '' login.keychain
# No settings: it never locks itself again, after a timeout or on sleep.
/usr/bin/security set-keychain-settings login.keychain
/usr/bin/security login-keychain -s login.keychain
/usr/bin/security default-keychain -s login.keychain

# Without a guest agent, `tart stop` powers the VM off at once, so shut macOS
# down from inside first, with provision.sh's key, and power off only what is
# still running after 40s.
# shellcheck disable=SC2329 # called by the trap below
stop_vm() {
  local ip waited=0
  log "shutting $VM_NAME down"
  if [[ -f $KEY_DIR/config ]] && ip=$(tart ip "$VM_NAME"); then
    timeout 15 ssh -F "$KEY_DIR/config" "$ip" sudo shutdown -h now </dev/null >&2 || true
    while kill -0 "$vm" 2>/dev/null && ((waited < 40)); do
      sleep 1
      waited=$((waited + 1))
    done
  fi
  if kill -0 "$vm" 2>/dev/null; then
    log "powering $VM_NAME off"
    tart stop "$VM_NAME" >&2 || kill "$vm" 2>/dev/null || true
  fi
}

log "starting $VM_NAME"
tart run --no-graphics --no-audio --no-clipboard "$VM_NAME" &
vm=$!
trap stop_vm TERM INT

status=0
wait "$vm" || status=$?
# A signal interrupts `wait`; after stop_vm, wait for the VM to be gone.
while kill -0 "$vm" 2>/dev/null; do
  status=0
  wait "$vm" || status=$?
done
log "$VM_NAME stopped (exit status $status)"
exit "$status"
