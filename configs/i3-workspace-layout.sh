#!/usr/bin/env bash
# Switch keyboard layout based on workspace.
# Workspace 10 uses qwerty; all others use dvp.

i3-msg -t subscribe '["workspace"]' | while read -r event; do
  workspace=$(echo "$event" | jq -r '.current.name // empty')
  [ -z "$workspace" ] && continue

  case "$workspace" in
    10-GAME) setxkbmap -layout us ;;
    *)       setxkbmap -layout us -variant dvp ;;
  esac
done
