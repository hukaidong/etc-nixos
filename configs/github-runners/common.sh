# Helpers shared by the runner daemons' scripts on the Mac Studio: the Linux
# runner's launcher (configs/github-runner-linux/launcher.sh) and the macOS
# runner VM's scripts (configs/github-runner-macos-vm/). The Nix modules in
# darwin/services/ put this file in front of each script.

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

# wait_for SECONDS WHAT COMMAND...: retry COMMAND every 5s until it succeeds.
wait_for() {
  local timeout=$1 what=$2 waited=0
  shift 2
  until "$@" >/dev/null 2>&1; do
    if ((waited >= timeout)); then
      log "gave up after ${timeout}s waiting for $what"
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

# github METHOD PATH [CURL_ARGS...]: GitHub REST call with the organization
# token in $token; prints the body. The token goes through a file descriptor
# so it never appears in `ps`.
github() {
  local method=$1 path=$2 response status
  shift 2
  response=$(curl --silent --show-error --retry 3 \
    --request "$method" \
    --header @<(printf 'Authorization: Bearer %s\n' "$token") \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --write-out '\n%{http_code}' \
    "$@" "https://api.github.com$path") || {
    log "GitHub API $method $path: request failed"
    return 1
  }
  status=${response##*$'\n'}
  response=${response%$'\n'*}
  if [[ $status != 2?? ]]; then
    log "GitHub API $method $path: HTTP $status ${response:0:300}"
    return 1
  fi
  printf '%s\n' "$response"
}
