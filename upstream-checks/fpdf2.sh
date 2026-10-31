#!/usr/bin/env bash
#
# fpdf2 -- test_image_with_explicit_dimensions fails against its Pillow-12
# reference PDF under Pillow 13.
#
# fpdf2 2.8.9's suite compares generated PDFs byte-for-byte with committed
# references.  Pillow 13 changes PNG decoding, so
# test/image/image_with_explicit_dimensions.pdf (generated with Pillow 12,
# md5 c7b6e70b...) no longer matches the bytes we generate (md5 6732d6d8...)
# and checkPhase fails, keeping the output out of cache.nixos.org.
#
# Upstream:
#   https://github.com/py-pdf/fpdf2/issues/2085
#   https://github.com/NixOS/nixpkgs/issues/580380
# Fixed upstream by regenerating the reference for Pillow 13 (py-pdf/fpdf2#2043,
# commit 597cfff), shipped in 2.9.0.
#
# Workaround (flake.nix, extraPkgsOverlay): while fpdf2 < 2.9.0 and Pillow is
# 13.x, override python313's fpdf2 and copy the 2.9.0 reference over the 2.8.9
# one, so the rest of the suite still runs.  nixpkgs release-26.05 instead
# deselects the test (NixOS/nixpkgs#580486), which also makes our override
# unnecessary.
#
# Probe: look at the *unpatched* fpdf2 from the pinned nixpkgs rev.  A version
# >= 2.9.0, or nixpkgs having deselected the test, clears the workaround
# without a build.  Otherwise build it with tests enabled; success means the
# pin is fixed and the override can go.
#
# Verdict:
#   0  unpatched pinned fpdf2 still fails -> keep the override
#   1  unpatched pinned fpdf2 builds -> drop the override and this script
#   2  inconclusive (network, unexpected build failure, missing tools)
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
lock="$root/flake.lock"
test_name="test_image_with_explicit_dimensions"

echo "## fpdf2"
echo "   workaround: flake.nix extraPkgsOverlay -> python313 fpdf2 postPatch"
echo "               replaces the Pillow-12 reference PDF with the 2.9.0 one"
echo "               while fpdf2 < 2.9.0 and Pillow is 13.x."
echo "   upstream:   https://github.com/py-pdf/fpdf2/issues/2085 (fixed in 2.9.0)"

if ! command -v nix >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "   => inconclusive: nix and jq must be on PATH"
  exit 2
fi
if [ ! -r "$lock" ]; then
  echo "   => inconclusive: cannot read $lock"
  exit 2
fi

# Resolve the node the root 'nixpkgs' input points to.  The bare
# `.nodes.nixpkgs` key can be an unrelated follows, so go through root.inputs.
node="$(jq -r '.nodes.root.inputs.nixpkgs' "$lock")"
rev="$(jq -r --arg k "$node" '.nodes[$k].locked.rev' "$lock")"
if [ -z "$rev" ] || [ "$rev" = "null" ]; then
  echo "   => inconclusive: cannot resolve the pinned nixpkgs rev"
  exit 2
fi

ref="github:NixOS/nixpkgs/$rev"
pkg="$ref#python313Packages.fpdf2"
echo "   pinned:     ${rev:0:12}"

# --- 1. cheap checks ---------------------------------------------------------
# Ask the pinned nixpkgs itself whether it already carries a fix, so the common
# "flake.lock finally moved" case does not need a two-minute test run.
info="$(nix eval --json --apply '
  p: {
    version = p.version;
    upstreamFixed = builtins.compareVersions p.version "2.9.0" >= 0;
    nixpkgsDisabled = builtins.elem "test_image_with_explicit_dimensions" (p.disabledTests or []);
  }' "$pkg" 2>/dev/null)" || info=""

if [ -n "$info" ]; then
  version="$(jq -r '.version' <<<"$info")"
  echo "   version:    $version"

  if [ "$(jq -r '.upstreamFixed' <<<"$info")" = "true" ]; then
    echo "   => CLEAR: pinned nixpkgs ships fpdf2 $version (>= 2.9.0), which"
    echo "      includes upstream 597cfff (the Pillow-13 reference).  Remove the"
    echo "      python313 fpdf2 override in flake.nix and delete this script."
    exit 1
  fi

  if [ "$(jq -r '.nixpkgsDisabled' <<<"$info")" = "true" ]; then
    echo "   => CLEAR: pinned nixpkgs already deselects $test_name"
    echo "      (NixOS/nixpkgs#580486), so our fixture patch is redundant."
    echo "      Remove the python313 fpdf2 override in flake.nix and delete this"
    echo "      script."
    exit 1
  fi
fi

# --- 2. build the unpatched package with tests enabled -----------------------
echo "   building unpatched $pkg (runs the fpdf2 test suite) ..."
build_log="$(mktemp)" || {
  echo "   => inconclusive: cannot create a temporary file"
  exit 2
}
trap 'rm -f "$build_log"' EXIT

if nix build --no-link --print-out-paths "$pkg" >/dev/null 2>"$build_log"; then
  echo "   => CLEAR: unpatched fpdf2 builds with tests enabled at the pinned rev."
  echo "      Remove the python313 fpdf2 override in flake.nix and delete this"
  echo "      script."
  exit 1
fi

# --- 3. verdict --------------------------------------------------------------
# Only a checkPhase failure in the tracked test counts as "still needed"; any
# other build error is a probe failure, not evidence about the workaround.
# Read the log into a variable and use a case match: `grep -q` would close the
# pipe early, and `set -o pipefail` would then see nix log's SIGPIPE as failure.
drv="$(nix eval --raw "$pkg.drvPath" 2>/dev/null)" || drv=""
if [ -n "$drv" ]; then
  log="$(nix log "$drv" 2>/dev/null)" || log=""
  case "$log" in
    *"$test_name"*)
      echo "   => still needed: $test_name still fails at the pinned rev."
      exit 0
      ;;
  esac
fi

echo "   => inconclusive: the unpatched build failed for an unexpected reason:"
tail -n 5 "$build_log" | sed 's/^/      /'
exit 2
