#!/bin/bash
# Round-trip ThemeBook config write/read without touching the live file.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
export HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/.config/omarchy"

json='{"favorites":["tokyo-night"],"folders":[{"id":"dark","name":"Dark","themes":["nord"]}]}'
"$root/scripts/config" write "$json"
got=$("$root/scripts/config" read)
echo "$got" | jq -e '.favorites == ["tokyo-night"]' >/dev/null
echo "$got" | jq -e '.folders[0].id == "dark"' >/dev/null
echo "config ok"
