#!/bin/bash
# Guest half of provision.sh (same directory): the steps that run inside the
# macOS runner VM. provision.sh runs `/bin/bash -s -- COMMAND` over SSH as
# admin, who has passwordless sudo, and sends the variables COMMAND needs as
# assignments in front of this file on standard input, so no secret is ever
# in a command line. Every command is idempotent.
#
# macOS' /bin/bash is version 3.2: no associative arrays, mapfile, ${var,,}.
set -euo pipefail

# Markers of one-time steps.
state=/var/db/github-runner-vm

log() {
  echo "guest: $*" >&2
}

# authorize (PUBKEY): first contact, still with the image's password. Makes
# the provisioning key admin's only authorized key.
authorize() {
  mkdir -p ~/.ssh
  chmod 0700 ~/.ssh
  printf '%s\n' "$PUBKEY" >~/.ssh/authorized_keys
  chmod 0600 ~/.ssh/authorized_keys
}

# harden (SSHD_CONFIG): close what the public image leaves open to the VM
# network. Prints host-key=<type> <key> when it made new SSH host keys.
harden() {
  local conf=/etc/ssh/sshd_config.d/000-github-runner-vm.conf disabled

  sudo install -d -m 0755 "$state"

  # Key-only SSH for admin. nix-darwin later replaces the file with a link to
  # the same content; when the content changes, the old link (into the
  # read-only store) goes first.
  if [[ "$(cat "$conf" 2>/dev/null || true)" != "$SSHD_CONFIG" ]]; then
    log "restricting SSH to admin's authorized keys"
    sudo rm -f "$conf"
    printf '%s\n' "$SSHD_CONFIG" | sudo tee "$conf" >/dev/null
  fi
  # nix-darwin keeps the file it replaced next to it, where sshd's
  # `Include sshd_config.d/*` would still read it.
  sudo rm -f "$conf.before-nix-darwin"

  # The image's password is public. Nobody needs admin's password (sudo asks
  # for none), so it becomes a random one that is never stored. admin holds
  # the volume's SecureToken, so even root has to give the old password.
  if [[ ! -e $state/password ]]; then
    if dscl . -authonly admin admin >/dev/null 2>&1; then
      log "replacing admin's password with a random one"
      dscl . -passwd /Users/admin admin "$(openssl rand -base64 32)"
    fi
    sudo touch "$state/password"
  fi

  # Automatic login used the old password.
  if [[ -e /etc/kcpassword ]]; then
    log "turning off automatic login"
    sudo rm -f /etc/kcpassword
  fi
  if defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser >/dev/null 2>&1; then
    sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser
  fi

  # The image enables Screen Sharing (VNC, port 5900).
  disabled=$(sudo launchctl print-disabled system)
  if [[ $disabled != *'"com.apple.screensharing" => disabled'* ]]; then
    log "turning off Screen Sharing"
    sudo launchctl disable system/com.apple.screensharing
    sudo launchctl bootout system/com.apple.screensharing 2>/dev/null || true
  fi

  # Every copy of the image has the same, published SSH host keys. sshd
  # starts per connection, so the next connection uses the new ones.
  if [[ ! -e $state/host-keys ]]; then
    log "generating SSH host keys of its own"
    sudo find /etc/ssh -maxdepth 1 -name 'ssh_host_*' -delete
    sudo ssh-keygen -A >/dev/null
    sudo touch "$state/host-keys"
    echo "host-key=$(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)"
  fi
}

# grow-disk: after `tart set --disk-size`, macOS takes up the new space in its
# boot container when it boots. Grow it here if that did not happen.
grow_disk() {
  local sectors end free
  sectors=$(($(diskutil info -plist disk0 | plutil -extract TotalSize raw -o - -) / 512))
  # End of the last partition; the backup GPT takes the last 33 sectors.
  end=$(sudo gpt -r show disk0 2>/dev/null |
    awk '$4 == "GPT" && $5 == "part" && $1 + $2 > end { end = $1 + $2 } END { print end + 0 }')
  free=$((sectors - 33 - end))
  # Less than 1 GiB left over is alignment, not a grown disk.
  if ((end == 0 || free < 2097152)); then
    return
  fi
  log "growing the boot container by $((free / 2097152)) GiB"
  yes | sudo diskutil repairDisk disk0 >/dev/null 2>&1 || true
  if ! sudo diskutil apfs resizeContainer disk0s2 0 >&2; then
    log "could not grow the boot container (see https://tart.run/faq/#disk-resizing)"
  fi
}

# status: what provision.sh needs to decide on the next steps.
status() {
  echo "system=$(readlink /run/current-system 2>/dev/null || true)"
  if [[ -x /run/current-system/sw/bin/nix-daemon ]]; then
    echo "nix_daemon=/run/current-system/sw/bin/nix-daemon"
  elif [[ -x /nix/var/nix/profiles/default/bin/nix-daemon ]]; then
    echo "nix_daemon=/nix/var/nix/profiles/default/bin/nix-daemon"
  else
    echo "nix_daemon="
  fi
  if [[ -x /Library/Developer/CommandLineTools/usr/bin/clang ]]; then
    echo "clt=yes"
  else
    echo "clt=no"
  fi
}

# install-clt: the Xcode Command Line Tools, headless: with this marker,
# softwareupdate lists them.
install_clt() {
  local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  sudo touch "$marker"
  label=$(softwareupdate --list 2>/dev/null |
    sed -n 's/^.*Label: \(Command Line Tools.*\)$/\1/p' | tail -1)
  if [[ -z $label ]]; then
    sudo rm -f "$marker"
    log "softwareupdate offers no Command Line Tools"
    return 1
  fi
  log "installing $label"
  sudo softwareupdate --install "$label" >&2
  sudo rm -f "$marker"
}

# install-nix (INSTALLER): multi-user Nix from the official installer, which
# provision.sh copied to INSTALLER and which checks the hash of what it
# downloads. It adds Nix to /etc/zshrc and /etc/bashrc (interactive shells),
# which nix-darwin leaves alone here (darwin/system/nix.nix); it does not touch
# /etc/profile, which nix-darwin's checks would reject.
install_nix() {
  log "installing Nix"
  sh "$INSTALLER" --daemon --yes --no-channel-add >&2
  rm -f "$INSTALLER"
}

# trust-admin: provision.sh copies unsigned store paths in as admin. Until
# nix-darwin manages /etc/nix/nix.conf (and trusts admin itself), the
# installer's nix.conf has to.
trust_admin() {
  local profile=/nix/var/nix/profiles/default tries=0
  if [[ -e /run/current-system ]] || grep -qx 'trusted-users = root admin' /etc/nix/nix.conf; then
    return
  fi
  log "trusting admin in the installer's nix.conf"
  echo 'trusted-users = root admin' | sudo tee -a /etc/nix/nix.conf >/dev/null
  sudo launchctl kickstart -k system/org.nixos.nix-daemon
  # A query of a store path, through the daemon (admin is not root).
  until "$profile/bin/nix-store" --query --hash "$(readlink -f "$profile")" >/dev/null 2>&1; do
    if ((++tries > 30)); then
      log "the Nix daemon did not come back"
      return 1
    fi
    sleep 1
  done
}

# activate (SYSTEM): switch to the nix-darwin system SYSTEM, which
# provision.sh copied in, the way darwin-rebuild switch does.
activate() {
  if [[ $(readlink /run/current-system 2>/dev/null || true) == "$SYSTEM" ]]; then
    return
  fi
  # nix-darwin will not replace /etc files it does not know; on the first
  # activation, the Nix installer's nix.conf is one.
  if [[ ! -e /run/current-system && -f /etc/nix/nix.conf && ! -L /etc/nix/nix.conf ]]; then
    log "moving the installer's /etc/nix/nix.conf to nix.conf.before-nix-darwin"
    sudo mv /etc/nix/nix.conf /etc/nix/nix.conf.before-nix-darwin
  fi
  log "activating $SYSTEM"
  sudo -H "$SYSTEM/sw/bin/nix-env" --profile /nix/var/nix/profiles/system --set "$SYSTEM"
  sudo -H "$SYSTEM/activate" >&2
}

# registered (RUNNER_DIR): whether the runner has registered (exit status).
registered() {
  sudo test -f "$RUNNER_DIR/.runner"
}

# write-token (TOKEN, TOKEN_FILE, GROUP): hand the runner service a
# registration token, readable by root and the runner's group only. Until it
# has registered, the service exits right away and launchd starts it again
# (KeepAlive, and WatchPaths on the token file), so it finds the token within
# its 30s throttle interval.
write_token() {
  local tmp
  sudo install -d -m 0755 "$(dirname "$TOKEN_FILE")"
  tmp=$(sudo mktemp "$TOKEN_FILE.XXXXXX")
  printf '%s' "$TOKEN" | sudo tee "$tmp" >/dev/null
  sudo chown "root:$GROUP" "$tmp"
  sudo chmod 0440 "$tmp"
  sudo mv -f "$tmp" "$TOKEN_FILE"
}

# remove-token (TOKEN_FILE): a registration token works for an hour and can
# register more runners; jobs (same user as the runner) must not find it.
remove_token() {
  sudo rm -f "$TOKEN_FILE"
}

main() {
  # bash has read this whole file by now; nothing else may read the SSH
  # session's standard input.
  exec </dev/null
  case $1 in
  authorize) authorize ;;
  harden) harden ;;
  grow-disk) grow_disk ;;
  status) status ;;
  install-clt) install_clt ;;
  install-nix) install_nix ;;
  trust-admin) trust_admin ;;
  activate) activate ;;
  registered) registered ;;
  write-token) write_token ;;
  remove-token) remove_token ;;
  *)
    log "unknown command: $1"
    return 2
    ;;
  esac
}

main "$@"
