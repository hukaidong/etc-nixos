# Launcher for the containerized Linux GitHub Actions runner on the Mac Studio.
# darwin/services/github-runner-linux.nix wraps this file with
# writeShellApplication (strict mode, PATH) and runs it as a launchd daemon.
#
# Each run creates one ephemeral just-in-time runner, runs it in a fresh
# container until it has finished a job, and exits; launchd (KeepAlive) then
# starts the next run. The organization token stays on the host: the
# container only receives the single-use JIT config.
#
# Inputs (environment): ORG, RUNNER_NAME, RUNNER_GROUP, RUNNER_LABELS
# (comma-separated), TOKEN_FILE, DOCKERFILE, RUNNER_VERSION, NIX_VERSION,
# IMAGE_TAG, CACHE_VOLUMES (true/false), DOCKER_CONFIG_JSON; DOCKER_HOST and
# DOCKER_CONFIG for the docker CLI.

image_repo=github-runner-linux
image="$image_repo:$IMAGE_TAG"
base_repo=ghcr.io/actions/actions-runner
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

# The docker CLI finds the buildx plugin through this config.
mkdir -p "$DOCKER_CONFIG"
install -m 0644 "$DOCKER_CONFIG_JSON" "$DOCKER_CONFIG/config.json"

# sops-nix decrypts the token at boot, possibly after launchd started us.
wait_for 300 "the token in $TOKEN_FILE" test -s "$TOKEN_FILE"
token=$(<"$TOKEN_FILE")

# The VM daemon may still be booting, or downloading its disk image.
wait_for 900 "docker at $DOCKER_HOST" docker info

if ! docker image inspect "$image" >/dev/null 2>&1; then
  log "building $image (runner $RUNNER_VERSION, nix $NIX_VERSION)"
  docker build --pull --progress=plain --tag "$image" \
    --build-arg "RUNNER_VERSION=$RUNNER_VERSION" \
    --build-arg "NIX_VERSION=$NIX_VERSION" \
    - <"$DOCKERFILE"

  # Drop what earlier builds left: older image tags, the base images they
  # were built from, and their cache volumes.
  while read -r ref; do
    [[ $ref == "$image" || $ref == "$base_repo:$RUNNER_VERSION" ]] ||
      docker image rm "$ref" >/dev/null || true
  done < <(
    docker image ls --format '{{.Repository}}:{{.Tag}}' "$image_repo"
    docker image ls --format '{{.Repository}}:{{.Tag}}' "$base_repo"
  )
  while read -r volume; do
    [[ $volume == *"-$IMAGE_TAG" ]] || docker volume rm "$volume" >/dev/null || true
  done < <(docker volume ls --quiet --filter "label=$volume_label")
  docker image prune --force >/dev/null || true
fi

# A runner killed mid-job, or before it got one, stays registered (offline)
# under this name until GitHub drops it a day later. Clear it so the name is
# free for the new just-in-time runner.
docker rm --force "$RUNNER_NAME" >/dev/null 2>&1 || true
name_query=$(jq -rn --arg name "$RUNNER_NAME" '$name | @uri')
runners=$(github GET "/orgs/$ORG/actions/runners?name=$name_query&per_page=100")
while read -r id; do
  log "removing stale registration $id"
  github DELETE "/orgs/$ORG/actions/runners/$id" >/dev/null || true
done < <(jq -r --arg name "$RUNNER_NAME" '.runners[] | select(.name == $name) | .id' <<<"$runners")

groups=$(github GET "/orgs/$ORG/actions/runner-groups?per_page=100")
group_id=$(jq -r --arg group "$RUNNER_GROUP" '.runner_groups[] | select(.name == $group) | .id' <<<"$groups")
if [[ -z $group_id ]]; then
  log "no runner group named '$RUNNER_GROUP' in $ORG"
  exit 1
fi

request=$(jq -n \
  --arg name "$RUNNER_NAME" \
  --argjson group "$group_id" \
  --arg labels "$RUNNER_LABELS" \
  '{name: $name, runner_group_id: $group, labels: ($labels | split(",")), work_folder: "_work"}')
jit=$(github POST "/orgs/$ORG/actions/runners/generate-jitconfig" --data-binary "$request")
ACTIONS_RUNNER_INPUT_JITCONFIG=$(jq -r '.encoded_jit_config // empty' <<<"$jit")
if [[ -z $ACTIONS_RUNNER_INPUT_JITCONFIG ]]; then
  log "GitHub returned no just-in-time runner config"
  exit 1
fi
# Passed by name to `docker run --env`, so it stays out of the argv; the
# runner removes it from its environment before any job step runs.
export ACTIONS_RUNNER_INPUT_JITCONFIG

mounts=()
if [[ $CACHE_VOLUMES == true ]]; then
  # Caches that outlive a job: the Nix store, rustup toolchains and cargo's
  # registry. Named by image tag, so a rebuilt image starts them afresh.
  for cache in nix:/nix rustup:/home/runner/.rustup cargo:/home/runner/.cargo; do
    volume="$RUNNER_NAME-${cache%%:*}-$IMAGE_TAG"
    docker volume inspect "$volume" >/dev/null 2>&1 ||
      docker volume create --label "$volume_label" "$volume" >/dev/null
    mounts+=(--mount "type=volume,source=$volume,target=${cache#*:}")
  done
fi

log "starting $RUNNER_NAME from $image"
# The runner's diagnostic logs stay in the container; its console lines
# (connected, running job, job finished) land in this daemon's log.
exec docker run --rm --init --pull never \
  --name "$RUNNER_NAME" \
  --env ACTIONS_RUNNER_INPUT_JITCONFIG \
  --env ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=false \
  "${mounts[@]}" \
  "$image" /home/runner/run.sh
