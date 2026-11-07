#!/bin/bash
# Rename user themes only. Stock stays. Symlink targets stay put.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
rename=$root/scripts/rename

fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
export HOME=$fake/home
export OMARCHY_PATH=$fake/omarchy

mkdir -p "$HOME/.config/omarchy/themes/old-theme/backgrounds"
mkdir -p "$HOME/.config/omarchy/backgrounds/old-theme"
mkdir -p "$HOME/.config/omarchy/themes/taken"
mkdir -p "$HOME/.local/state/omarchy/current"
mkdir -p "$HOME/.local/state/omarchy/theme-backgrounds"
mkdir -p "$OMARCHY_PATH/themes/catppuccin"
mkdir -p "$HOME/real/link-theme/backgrounds"
printf 'wall\n' >"$HOME/.config/omarchy/themes/old-theme/backgrounds/wall.jpg"
printf 'extra\n' >"$HOME/.config/omarchy/backgrounds/old-theme/extra.jpg"
printf 'old-theme\n' >"$HOME/.local/state/omarchy/current/theme.name"
ln -s "$HOME/.config/omarchy/themes/old-theme/backgrounds/wall.jpg" \
  "$HOME/.local/state/omarchy/current/background"
printf '%s\n' "$HOME/.config/omarchy/themes/old-theme/backgrounds/wall.jpg" \
  >"$HOME/.local/state/omarchy/theme-backgrounds/old-theme"
printf 'keep\n' >"$HOME/real/link-theme/backgrounds/keep.jpg"
ln -s "$HOME/real/link-theme" "$HOME/.config/omarchy/themes/link-theme"

out=$("$rename" old-theme new-theme)
echo "$out" | jq -e '.ok == true and .from == "old-theme" and .to == "new-theme"' >/dev/null
[[ -d $HOME/.config/omarchy/themes/new-theme/backgrounds ]]
[[ ! -e $HOME/.config/omarchy/themes/old-theme ]]
[[ -f $HOME/.config/omarchy/backgrounds/new-theme/extra.jpg ]]
[[ ! -e $HOME/.config/omarchy/backgrounds/old-theme ]]
[[ $(tr -d '\n' <"$HOME/.local/state/omarchy/current/theme.name") == new-theme ]]
echo "$out" | jq -e --arg old "$HOME/.config/omarchy/themes/old-theme" --arg new "$HOME/.config/omarchy/themes/new-theme" \
  'any(.rewrites[]; .from == $old and .to == $new)' >/dev/null
target=$(readlink "$HOME/.local/state/omarchy/current/background")
[[ $target == "$HOME/.config/omarchy/themes/new-theme/backgrounds/wall.jpg" ]]
[[ -f $HOME/.local/state/omarchy/theme-backgrounds/new-theme ]]
[[ ! -e $HOME/.local/state/omarchy/theme-backgrounds/old-theme ]]

out=$("$rename" link-theme linked)
echo "$out" | jq -e '.ok == true and (.rewrites | length) == 0' >/dev/null
[[ $(readlink "$HOME/.config/omarchy/themes/linked") == "$HOME/real/link-theme" ]]
[[ -f $HOME/real/link-theme/backgrounds/keep.jpg ]]
[[ ! -e $HOME/.config/omarchy/themes/link-theme ]]

if "$rename" new-theme taken >"$fake/exists.json" 2>/dev/null; then
  echo "rename over existing theme" >&2
  exit 1
fi
jq -e '.error == "exists"' >/dev/null <"$fake/exists.json"
[[ -d $HOME/.config/omarchy/themes/new-theme ]]

if "$rename" catppuccin other >"$fake/stock.json" 2>/dev/null; then
  echo "stock theme renamed" >&2
  exit 1
fi
jq -e '.error == "not-user"' >/dev/null <"$fake/stock.json"
[[ -d $OMARCHY_PATH/themes/catppuccin ]]

if "$rename" '../x' safe >"$fake/bad.json" 2>/dev/null; then
  echo "bad slug renamed" >&2
  exit 1
fi
jq -e '.error == "invalid-slug"' >/dev/null <"$fake/bad.json"

echo "rename ok"
