# Launcher for the containerized Linux GitHub Actions runner on the Mac Studio.
# darwin/services/github-runner-linux.nix wraps this file with
# writeShellApplication (strict mode, PATH) and runs it as a launchd daemon.
#
# Each run registers one ephemeral runner, runs it in a fresh container until
# it has finished a job, and exits; launchd (KeepAlive) then starts the next
# run. The organization token stays on the host: the container only receives
# a short-lived registration token, on its standard input, which the image's
# entrypoint (entrypoint.sh in this directory) hands to config.sh.
#
# Inputs (environment): ORG, RUNNER_NAME, RUNNER_GROUP, RUNNER_LABELS (extra
# labels, comma-separated, possibly empty), TOKEN_FILE, IMAGE_STREAM (writes
# the Nix-built image to stdout, in `docker load` format), IMAGE_NAME,
# IMAGE_TAG, IMAGE_HOME (the home of the image's job user), CACHE_VOLUMES
# (true/false); DOCKER_HOST and DOCKER_CONFIG for the docker CLI.

image="$IMAGE_NAME:$IMAGE_TAG"
volume_label="org.nixos.github-runner-linux=$RUNNER_NAME"

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

# github METHOD PATH [CURL_ARGS...]: GitHub REST call; prints the body. The
# token goes through a file descriptor so it never appears in `ps`.
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

# sops-nix decrypts the token at boot, possibly after launchd started us.
wait_for 300 "the token in $TOKEN_FILE" test -s "$TOKEN_FILE"
token=$(<"$TOKEN_FILE")

# The VM daemon may still be booting, or downloading its disk image.
wait_for 900 "docker at $DOCKER_HOST" docker info

if ! docker image inspect "$image" >/dev/null 2>&1; then
  # The image is already built: the stream script assembles it from the Nix
  # store on the fly, so loading needs no network.
  log "loading $image"
  "$IMAGE_STREAM" | docker load

  # Drop what earlier images left: their tags and their cache volumes.
  while read -r ref; do
    [[ $ref == "$image" ]] || docker image rm "$ref" >/dev/null || true
  done < <(docker image ls --format '{{.Repository}}:{{.Tag}}' "$IMAGE_NAME")
  while read -r volume; do
    [[ $volume == *"-$IMAGE_TAG" ]] || docker volume rm "$volume" >/dev/null || true
  done < <(docker volume ls --quiet --filter "label=$volume_label")
  docker image prune --force >/dev/null || true
fi

# A runner killed mid-job, or before it got one, leaves its container behind
# if docker did not get to remove it. Its registration (offline) is replaced
# by the new runner of the same name: the entrypoint passes --replace.
docker rm --force "$RUNNER_NAME" >/dev/null 2>&1 || true

# Valid for an hour, but used once, right away.
registration=$(github POST "/orgs/$ORG/actions/runners/registration-token")
registration_token=$(jq -r '.token // empty' <<<"$registration")
if [[ -z $registration_token ]]; then
  log "GitHub returned no registration token"
  exit 1
fi

# config.sh options; it adds the labels self-hosted, Linux and the
# architecture itself.
runner_args=(--url "https://github.com/$ORG" --name "$RUNNER_NAME" --runnergroup "$RUNNER_GROUP")
if [[ -n $RUNNER_LABELS ]]; then
  runner_args+=(--labels "$RUNNER_LABELS")
fi

mounts=()
if [[ $CACHE_VOLUMES == true ]]; then
  # Caches that outlive a job: the Nix store (with its database), rustup
  # toolchains and cargo's registry, under the job user's home. Named by
  # image tag, so a new image starts them afresh; docker fills an empty volume
  # from the image, contents and owner, so the /nix volume starts with the
  # image's store and every volume belongs to the job user.
  for cache in nix:/nix rustup:"$IMAGE_HOME/.rustup" cargo:"$IMAGE_HOME/.cargo"; do
    volume="$RUNNER_NAME-${cache%%:*}-$IMAGE_TAG"
    docker volume inspect "$volume" >/dev/null 2>&1 ||
      docker volume create --label "$volume_label" "$volume" >/dev/null
    mounts+=(--mount "type=volume,source=$volume,target=${cache#*:}")
  done
fi

log "starting $RUNNER_NAME from $image"
# The registration token goes in on the container's standard input, so it is
# in neither an argv nor the container's environment, which jobs could read
# (/proc/1/environ). The runner's diagnostic logs stay in the container; its
# console lines (connected, running job, job finished) land in this daemon's
# log.
exec docker run --rm --init --interactive --pull never \
  --name "$RUNNER_NAME" \
  "${mounts[@]}" \
  "$image" "${runner_args[@]}" <<<"$registration_token"
