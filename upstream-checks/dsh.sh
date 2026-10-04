#!/usr/bin/env bash
#
# dsh -- DeepSeek Harness fails to boot on nix-built Node.js.
#
# nixpkgs builds nodejs with `zerocallusedregs` hardening, which breaks the
# `node-addon-require-builtin` native addon that `@deepseek-ai/dsh-app-boot`
# uses to reach Node internals.  Mounting any profile dies in
# installRuntimeInterception() with `Unsupported/no-getter`, so `dsh` cannot
# start at all.
#
# Upstream reports:
#   https://github.com/numtide/llm-agents.nix/issues/9994
#   https://github.com/NixOS/nixpkgs/issues/565667
#
# Workaround (not version-gated, so it needs a probe) -- commit d902a1b
# "fix(dsh): patch node-addon-require-builtin boot failure":
#   flake.nix `dsh-patched` rewrites the offending call in
#   dsh-app-boot/lib/index.js to a plain `createRequire` (the launcher already
#   runs node with --expose-internals).  It is wired in through
#   modules/packages/desktop.nix and modules/services/dsh.nix.
#
# Probe: build the *unpatched* dsh from upstream and actually boot the web
# profile with `dsh web --no-open --port 0`.  A healthy build prints
# "dsh web: http://..." and keeps serving, so we kill it as soon as that line
# appears; a broken build exits immediately with the node-addon error.  This is
# the exact code path the workaround dodges, and it exercises a real boot
# rather than a static check of the rewritten file.
#
# Verdict:
#   0  upstream dsh still fails to boot -> keep dsh-patched
#   1  upstream dsh boots -> update flake.lock, revert the override and the two
#      call sites, then delete this script
#   2  inconclusive (nix missing, build/network failure, unexpected error)
set -uo pipefail

pkg="dsh"
# Flake ref that provides the package we override; it redirects to
# github:numtide/llm-agents.nix.  We probe HEAD rather than the flake.lock pin
# because a pin can never become fixed on its own -- the question is whether
# updating flake.lock would let us drop the workaround.
ref="github:numtide/nix-ai-tools"

echo "## $pkg"
echo "   workaround: flake.nix dsh-patched -> rewrites the"
echo "               node-addon-require-builtin call in dsh-app-boot."
echo "   upstream:   $ref (node-addon-require-builtin on nix-built nodejs)"
echo "   probe:      unpatched \`dsh web --no-open --port 0\` (real boot)"

if ! command -v nix >/dev/null 2>&1; then
  echo "   => inconclusive: nix is not on PATH"
  exit 2
fi

work="$(mktemp -d)" || {
  echo "   => inconclusive: cannot create a temporary directory"
  exit 2
}
dsh_pid=""
cleanup() {
  if [ -n "$dsh_pid" ] && kill -0 "$dsh_pid" 2>/dev/null; then
    kill "$dsh_pid" 2>/dev/null
    wait "$dsh_pid" 2>/dev/null
  fi
  rm -rf "$work"
}
trap cleanup EXIT

# --- 1. build unpatched upstream dsh ----------------------------------------
echo "   building $ref#dsh ..."
build_log="$work/build.log"
out="$(nix build --no-link --print-out-paths "$ref#dsh" 2>"$build_log")"
build_rc=$?
if [ "$build_rc" -ne 0 ]; then
  echo "   => inconclusive: nix build failed (exit $build_rc)"
  tail -n 5 "$build_log" | sed 's/^/      /'
  exit 2
fi
out="$(printf '%s\n' "$out" | tail -n 1)"
if [ ! -x "$out/bin/dsh" ]; then
  echo "   => inconclusive: upstream package has no executable bin/dsh ($out)"
  exit 2
fi

# --- 2. boot it -------------------------------------------------------------
sample="$work/home"
mkdir -p "$sample"
boot_log="$work/boot.log"
DSH_HOME="$sample" "$out/bin/dsh" web --no-open --host 127.0.0.1 --port 0 >"$boot_log" 2>&1 &
dsh_pid=$!

booted=0
i=0
while [ "$i" -lt 90 ]; do
  if grep -q 'dsh web: http://' "$boot_log" 2>/dev/null; then
    booted=1
    break
  fi
  # an early exit means it crashed rather than served
  kill -0 "$dsh_pid" 2>/dev/null || break
  sleep 1
  i=$((i + 1))
done

if kill -0 "$dsh_pid" 2>/dev/null; then
  kill "$dsh_pid" 2>/dev/null
fi
wait "$dsh_pid" 2>/dev/null
dsh_pid=""

# --- 3. verdict -------------------------------------------------------------
if [ "$booted" -eq 1 ]; then
  url="$(grep -m1 -o 'http://[^/]*' "$boot_log")"
  echo "   => CLEAR: unpatched upstream dsh booted and served ($url)."
  echo "      Update flake.lock, revert d902a1b (the dsh-patched override and its"
  echo "      two call sites), then delete upstream-checks/dsh.sh."
  exit 1
fi

if grep -qi 'node-addon-require-builtin' "$boot_log"; then
  echo "   => still needed: upstream dsh aborts at boot with the addon error:"
  grep -m1 -i 'node-addon-require-builtin unsupported' "$boot_log" | sed 's/^/      /'
  exit 0
fi

echo "   => inconclusive: \`dsh web\` did not boot and the error was unexpected:"
tail -n 5 "$boot_log" | sed 's/^/      /'
exit 2
