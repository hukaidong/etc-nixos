#!/usr/bin/env bash
#
# Upstream check: pipx 1.8.0 checkPhase failure on nixos-26.05.
#
# Workaround: flake.nix overlay sets `pipx.overridePythonAttrs (_: { doCheck = false; })`
# because pipx's test suite asserts the pre-spacing package-specifier format
# (`black@ url`) while the newer `packaging` lib canonicalises with a space
# (`black @ url`).  Hydra fails the same way, so the build is not cached.
#
# This probe builds pipx *with its tests enabled* (plain nixpkgs, no override)
# at the pinned rev and on the live branch, to decide whether we can drop it.
#
# Exit codes (consumed by the upstream-check runner):
#   0  workaround still required
#   1  upstream path clear -> drop the override in flake.nix
#   2  inconclusive / probe error
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
lock="$root/flake.lock"

echo "## pipx"
echo "   workaround: flake.nix overlay -> pipx.overridePythonAttrs (_: { doCheck = false; })"

if [ ! -r "$lock" ]; then
  echo "   => inconclusive: cannot read $lock"
  exit 2
fi

# Resolve the node the root 'nixpkgs' input points to. The bare `.nodes.nixpkgs`
# key is an unrelated follows (unstable); the real one is renamed (e.g. nixpkgs_2).
node="$(jq -r '.nodes.root.inputs.nixpkgs' "$lock")"
rev="$(jq -r --arg k "$node" '.nodes[$k].locked.rev' "$lock")"
branch="$(jq -r --arg k "$node" '.nodes[$k].original.ref // "nixos-26.05"' "$lock")"

# Build the un-overridden pipx (default doCheck => tests run); success == fixed.
probe() {
  nix build --no-link "$1" >/dev/null 2>&1
}

pinned_clear=1
if [ -n "$rev" ] && [ "$rev" != "null" ]; then
  printf '   pinned rev %s builds pipx w/ tests... ' "${rev:0:12}"
  if probe "github:NixOS/nixpkgs/$rev#pipx"; then echo "YES"; pinned_clear=0; else echo "no"; fi
fi

printf '   live %s builds pipx w/ tests... ' "$branch"
live_clear=1
if probe "github:NixOS/nixpkgs/$branch#pipx"; then echo "YES"; live_clear=0; else echo "no"; fi

if [ "$pinned_clear" -eq 0 ]; then
  echo "   => CLEAR: pipx already builds at the pinned rev; remove the override in flake.nix."
  exit 1
elif [ "$live_clear" -eq 0 ]; then
  echo "   => CLEAR after update: run 'nix flake update nixpkgs', then remove the override in flake.nix."
  exit 1
fi

echo "   => still needed: upstream pipx tests still fail."
exit 0
