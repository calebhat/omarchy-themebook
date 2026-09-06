#!/bin/bash
# Delete user theme + extra wallpapers; never stock; never the current theme.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
remove=$root/scripts/remove

fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
export HOME=$fake/home
export OMARCHY_PATH=$fake/omarchy

mkdir -p "$HOME/.config/omarchy/themes/gone/backgrounds"
mkdir -p "$HOME/.config/omarchy/backgrounds/gone"
mkdir -p "$HOME/.config/omarchy/themes/keep-current"
mkdir -p "$HOME/.local/state/omarchy/current"
mkdir -p "$OMARCHY_PATH/themes/catppuccin"
mkdir -p "$HOME/.config/omarchy/themes/overlay-stock"
printf 'keep-current\n' >"$HOME/.local/state/omarchy/current/theme.name"
printf 'x' >"$HOME/.config/omarchy/themes/gone/colors.toml"
printf 'x' >"$HOME/.config/omarchy/backgrounds/gone/wall.jpg"
printf 'x' >"$OMARCHY_PATH/themes/catppuccin/colors.toml"
printf 'x' >"$HOME/.config/omarchy/themes/overlay-stock/colors.toml"
printf 'x' >"$HOME/.config/omarchy/themes/keep-current/colors.toml"

out=$("$remove" gone)
echo "$out" | jq -e '.ok == true and .removedTheme == true and .removedBackgrounds == true' >/dev/null
[[ ! -e $HOME/.config/omarchy/themes/gone ]]
[[ ! -e $HOME/.config/omarchy/backgrounds/gone ]]

if "$remove" keep-current >"$fake/current.json" 2>/dev/null; then
  echo "current theme was deleted" >&2
  exit 1
fi
jq -e '.ok == false and .error == "current"' >/dev/null <"$fake/current.json"
[[ -d $HOME/.config/omarchy/themes/keep-current ]]

if "$remove" catppuccin >"$fake/stock.json" 2>/dev/null; then
  echo "stock theme was deleted" >&2
  exit 1
fi
jq -e '.ok == false and .error == "not-user"' >/dev/null <"$fake/stock.json"
[[ -d $OMARCHY_PATH/themes/catppuccin ]]

out=$("$remove" overlay-stock)
echo "$out" | jq -e '.ok == true and .removedTheme == true' >/dev/null
[[ ! -e $HOME/.config/omarchy/themes/overlay-stock ]]
[[ -d $OMARCHY_PATH/themes/catppuccin ]]

if "$remove" '../etc' >"$fake/bad.json" 2>/dev/null; then
  echo "traversal slug accepted" >&2
  exit 1
fi
jq -e '.error == "invalid-slug"' >/dev/null <"$fake/bad.json"

echo "remove ok"
