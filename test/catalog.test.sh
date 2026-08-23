#!/bin/bash
# Smoke-test ThemeBook catalog JSON.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

write_png() {
  python3 - "$1" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(bytes.fromhex(
  "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
  "0000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082"
))
PY
}

# Isolated home: a user theme without colors.toml used to abort the whole
# producer (set -e + get_color return 1). Stock and the incomplete theme
# must both appear.
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
mkdir -p "$fake/home/.config/omarchy/themes/aether/backgrounds"
mkdir -p "$fake/home/.config/omarchy/themes/bad theme/backgrounds"
mkdir -p "$fake/home/.local/state/omarchy/current"
mkdir -p "$fake/omarchy/themes/catppuccin/backgrounds"
write_png "$fake/home/.config/omarchy/themes/aether/backgrounds/wall.png"
write_png "$fake/home/.config/omarchy/themes/bad theme/backgrounds/wall.png"
write_png "$fake/omarchy/themes/catppuccin/preview.png"
write_png "$fake/omarchy/themes/catppuccin/backgrounds/1.jpg"
printf 'accent = "#aabbcc"\nbackground = "#111111"\nforeground = "#eeeeee"\nmode = "dark"\n' \
  >"$fake/omarchy/themes/catppuccin/colors.toml"
printf 'catppuccin\n' >"$fake/home/.local/state/omarchy/current/theme.name"

isolated=$(HOME="$fake/home" OMARCHY_PATH="$fake/omarchy" THEMEBOOK_CATALOG_WRAPPED=1 "$root/scripts/catalog")
echo "$isolated" | jq -e 'type == "array" and length == 2' >/dev/null
echo "$isolated" | jq -e 'any(.[]; .slug == "aether" and .source == "user" and (.backgrounds | length) > 0)' >/dev/null
echo "$isolated" | jq -e 'any(.[]; .slug == "catppuccin" and .source == "stock" and .preview != "")' >/dev/null
echo "$isolated" | jq -e 'all(.[]; .slug != "bad theme")' >/dev/null

out=$("$root/scripts/catalog")
echo "$out" | jq -e 'type == "array" and length > 0' >/dev/null
echo "$out" | jq -e 'all(.[]; has("slug") and has("name") and has("source") and has("colors"))' >/dev/null
echo "$out" | jq -e 'any(.[]; .current == true)' >/dev/null
echo "catalog ok ($("$root/scripts/catalog" | jq 'length') themes, isolated $(echo "$isolated" | jq 'length'))"
