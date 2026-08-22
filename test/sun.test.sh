#!/bin/bash
# sunwait helper rejects non-numeric coordinates.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
export HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/.local/state/omarchy/settings"
printf '%s\n' '{"latitude":"nope","longitude":-89}' >"$HOME/.local/state/omarchy/settings/weather.json"
got=$("$root/scripts/sun")
[[ $got == unknown ]]
printf '%s\n' '{"latitude":42.8,"longitude":-89.1}' >"$HOME/.local/state/omarchy/settings/weather.json"
got=$("$root/scripts/sun")
[[ $got == day || $got == night || $got == unknown ]]
echo "sun ok"
