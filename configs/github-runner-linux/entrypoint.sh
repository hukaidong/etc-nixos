# Entrypoint of the image the containerized Linux GitHub Actions runner runs
# every job in. darwin/services/github-runner-linux.nix builds the image with
# Nix and puts a shebang, strict mode and GITHUB_RUNNER (nixpkgs'
# github-runner package) in front of this file.
#
# Registers an ephemeral runner with the registration token that launcher.sh
# writes to standard input, runs it until it has finished one job, and exits.
# The arguments are config.sh options naming the runner: --url, --name,
# --runnergroup and, if there are extra labels, --labels.
#
# The runner lives in the read-only Nix store and cannot update itself, so it
# registers with --disableupdate: GitHub then never sends it an update, and a
# new runner release arrives with the next flake.lock update instead. A
# just-in-time config cannot carry that setting, which is why this uses a
# registration token.

token=
IFS= read -r token || true
if [[ -z $token ]]; then
  echo "expected a registration token on standard input" >&2
  exit 1
fi

# The image runs this as its unprivileged job user, which owns the runner's
# directory, the Nix store and its home. The token reaches config.sh through
# the environment rather than its argv, and the runner removes it from there
# before doing anything else.
ACTIONS_RUNNER_INPUT_TOKEN=$token \
  "$GITHUB_RUNNER/bin/config.sh" --unattended --ephemeral --disableupdate \
  --replace --work _work "$@"
unset token

exec "$GITHUB_RUNNER/bin/Runner.Listener" run --startuptype service
