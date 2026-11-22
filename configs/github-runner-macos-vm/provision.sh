# Provisioner of the macOS GitHub Actions runner VM on the Mac Studio.
# darwin/services/github-runner-macos-vm.nix puts configs/github-runners/common.sh
# and the defaults of the inputs below in front of this file, wraps it with
# writeShellApplication (strict mode, PATH) and runs it as a launchd daemon
# (KeepAlive) as the hidden _github-runner-macos user. Any failure exits, and
# launchd tries again.
#
# Brings the VM that vm.sh runs to the state this flake describes, over SSH,
# then checks again every INTERVAL seconds; with --once, it makes one pass and
# exits. Each pass first waits for vm.sh to run the VM, which the first time
# means creating it from the image (a download of about 30 GB). The steps are
# idempotent and say nothing when there is nothing to do; the guest half of
# each is a command of GUEST_SCRIPT (guest.sh):
#
#  1. First contact: log in with the image's public admin password and make
#     this daemon's key (KEY_DIR, generated here) the only authorized key.
#  2. Harden the guest: key-only SSH for admin (SSHD_CONFIG), a random admin
#     password, no automatic login, no Screen Sharing, SSH host keys of its
#     own (pinned in KEY_DIR). The Colima VM, where Linux jobs run, shares the
#     VM network, so the image's well-known login must stop working.
#  3. Check that the boot container fills the disk that vm.sh grew.
#  4. Install the Xcode Command Line Tools, and Nix with the pinned installer
#     NIX_INSTALLER, if missing.
#  5. Deploy GUEST_SYSTEM, the guest's nix-darwin system, built on this host:
#     copy its closure in and activate it, unless the guest runs it already.
#  6. Register the guest's runner if it has not registered: mint a
#     registration token with the organization token (TOKEN_FILE), write it to
#     GUEST_TOKEN_FILE, where the runner service picks it up, and delete it
#     once the runner has registered (or after 3 minutes). The organization
#     token never leaves the host.
#
# Inputs (environment): STATE_DIR (on an external volume, it must be mounted),
# TART_HOME, VM_NAME, KEY_DIR, TOKEN_FILE, ORG, GUEST_SYSTEM, GUEST_SCRIPT,
# NIX_INSTALLER, SSHD_CONFIG, GUEST_TOKEN_FILE, GUEST_RUNNER_DIR,
# GUEST_RUNNER_GROUP, INTERVAL; REGISTRATION_TOKEN_FILE
# (for tests: a file with the registration token to use; GitHub is not asked).

once=
if [[ ${1:-} == --once ]]; then
  once=1
fi

github-runners-state-dir "$STATE_DIR"
cd "$STATE_DIR"
export TART_HOME

key=$KEY_DIR/id_ed25519
known_hosts=$KEY_DIR/known_hosts
ssh_config=$KEY_DIR/config
# The guest's address, from tart; set by find_vm.
ip=

setup_key() {
  install -d -m 0700 "$KEY_DIR"
  if [[ ! -f $key ]]; then
    log "generating the provisioning key $key"
    ssh-keygen -q -t ed25519 -N '' -C "$VM_NAME provisioner" -f "$key"
  fi
  # This key only, never an agent's or ~/.ssh's. The host key is pinned under
  # the VM's name rather than its address, which DHCP may change. vm.sh uses
  # this file too.
  cat >"$ssh_config.tmp" <<EOF
Host *
  User admin
  HostKeyAlias $VM_NAME
  IdentityFile $key
  IdentitiesOnly yes
  IdentityAgent none
  PreferredAuthentications publickey
  UserKnownHostsFile $known_hosts
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking accept-new
  UpdateHostKeys no
  BatchMode yes
  ConnectTimeout 10
  ServerAliveInterval 15
  ServerAliveCountMax 4
  LogLevel ERROR
EOF
  mv -f "$ssh_config.tmp" "$ssh_config"
}

# guest_input [NAME=VALUE...]: the standard input of a guest command: the
# assignments, then guest.sh.
guest_input() {
  local assignment
  for assignment in "$@"; do
    printf '%s=%q\n' "${assignment%%=*}" "${assignment#*=}"
  done
  cat "$GUEST_SCRIPT"
}

# guest COMMAND [NAME=VALUE...]: run guest.sh's COMMAND in the VM as admin.
guest() {
  local command=$1
  shift
  guest_input "$@" | ssh -F "$ssh_config" "$ip" /bin/bash -s -- "$command"
}

ssh_works() {
  ssh -F "$ssh_config" "$ip" true </dev/null >/dev/null 2>&1
}

sshd_up() {
  [[ -n $(ssh-keyscan -T 5 -t ed25519 "$ip" 2>/dev/null) ]]
}

# First contact with a VM fresh from the image, whose password is public.
bootstrap() {
  guest_input PUBKEY="$(<"$key.pub")" |
    SSHPASS='admin' sshpass -e ssh -F /dev/null \
      -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=10 \
      -o IdentitiesOnly=yes -o IdentityAgent=none -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password,keyboard-interactive \
      -o NumberOfPasswordPrompts=1 \
      "admin@$ip" /bin/bash -s -- authorize 2>/dev/null
}

# Whether vm.sh runs the VM. While vm.sh is still creating it, the VM does
# not exist yet, and `tart ip` fails at once, whatever its --wait.
vm_running() {
  [[ $(tart get "$VM_NAME" --format json 2>/dev/null | jq -r .Running) == true ]]
}

find_vm() {
  local since
  if ! vm_running; then
    log "waiting for vm.sh to run $VM_NAME (the first time, it creates it from the image first)"
    wait_for 3600 "vm.sh to run $VM_NAME" vm_running
  fi
  since=$SECONDS
  if ! ip=$(tart ip "$VM_NAME" --wait 600) || [[ -z $ip ]]; then
    log "$VM_NAME is running but has no address after $((SECONDS - since))s"
    return 1
  fi
  wait_for 600 "SSH on $VM_NAME ($ip)" sshd_up
}

connect() {
  if ssh_works; then
    return
  fi
  if bootstrap; then
    log "authorized the provisioning key in $VM_NAME, a new VM"
    # A host key pinned for an earlier VM of this name no longer applies.
    rm -f "$known_hosts"
    if ssh_works; then
      return
    fi
  fi
  log "cannot log in to $VM_NAME ($ip) with $key, nor with the image's password:"
  ssh -F "$ssh_config" "$ip" true </dev/null || true
  log "if the VM was replaced on purpose, delete $known_hosts"
  return 1
}

harden() {
  local output
  output=$(guest harden SSHD_CONFIG="$(<"$SSHD_CONFIG")")
  if [[ $output == host-key=* ]]; then
    printf '%s %s\n' "$VM_NAME" "${output#host-key=}" >"$known_hosts"
    log "pinned the new SSH host key of $VM_NAME"
  fi
}

# The guest's status (guest.sh status) in the array status.
declare -A status
read_status() {
  local output line
  output=$(guest status)
  status=()
  while IFS= read -r line; do
    status[${line%%=*}]=${line#*=}
  done <<<"$output"
}

install_tools() {
  local installer=/private/tmp/github-runner-nix-installer
  read_status
  if [[ ${status[clt]} != yes ]]; then
    guest install-clt
  fi
  if [[ -z ${status[nix_daemon]} ]]; then
    ssh -F "$ssh_config" "$ip" "cat > $installer" <"$NIX_INSTALLER"
    guest install-nix INSTALLER="$installer"
  fi
}

deploy() {
  read_status
  if [[ ${status[system]} == "$GUEST_SYSTEM" ]]; then
    return
  fi

  guest trust-admin
  log "copying $GUEST_SYSTEM to $VM_NAME"
  NIX_SSHOPTS="-F $ssh_config" nix --extra-experimental-features nix-command \
    copy --no-check-sigs \
    --to "ssh-ng://admin@$ip?remote-program=${status[nix_daemon]}" \
    "$GUEST_SYSTEM"
  guest activate SYSTEM="$GUEST_SYSTEM"
  log "$VM_NAME runs $GUEST_SYSTEM"
}

registration_token() {
  local response
  if [[ -n $REGISTRATION_TOKEN_FILE ]]; then
    printf '%s' "$(<"$REGISTRATION_TOKEN_FILE")"
    return
  fi
  # sops-nix decrypts the token at boot, possibly after launchd started us.
  wait_for 300 "the token in $TOKEN_FILE" test -s "$TOKEN_FILE" || return 1
  token=$(<"$TOKEN_FILE")
  response=$(github POST "/orgs/$ORG/actions/runners/registration-token") || return 1
  jq -r '.token // empty' <<<"$response"
}

register() {
  local registration tries=0
  if guest registered RUNNER_DIR="$GUEST_RUNNER_DIR"; then
    return
  fi
  registration=$(registration_token)
  if [[ -z $registration ]]; then
    log "got no registration token"
    return 1
  fi
  log "registering the runner in $VM_NAME"
  guest write-token TOKEN="$registration" TOKEN_FILE="$GUEST_TOKEN_FILE" \
    GROUP="$GUEST_RUNNER_GROUP"
  until guest registered RUNNER_DIR="$GUEST_RUNNER_DIR"; do
    if ((++tries > 36)); then
      guest remove-token TOKEN_FILE="$GUEST_TOKEN_FILE"
      log "the runner in $VM_NAME did not register within 3 minutes; its logs are in /var/log/github-runners/ in the VM"
      return 1
    fi
    sleep 5
  done
  guest remove-token TOKEN_FILE="$GUEST_TOKEN_FILE"
  log "the runner in $VM_NAME has registered"
}

provision() {
  find_vm
  connect
  harden
  guest grow-disk
  install_tools
  deploy
  register
}

setup_key
while true; do
  provision
  if [[ -n $once ]]; then
    break
  fi
  sleep "$INTERVAL"
done
