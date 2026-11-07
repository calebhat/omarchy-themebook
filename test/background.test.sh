#!/bin/bash
# Copy any theme background. Move and delete only user-owned files.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
bg=$root/scripts/background

fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
export HOME=$fake/home
export OMARCHY_PATH=$fake/omarchy

mkdir -p "$HOME/.config/omarchy/themes/mine/backgrounds"
mkdir -p "$HOME/.config/omarchy/themes/other/backgrounds"
mkdir -p "$HOME/.config/omarchy/backgrounds/mine"
mkdir -p "$OMARCHY_PATH/themes/stock/backgrounds"
mkdir -p "$HOME/.local/state/omarchy/current"
printf 'mine\n' >"$HOME/.config/omarchy/themes/mine/backgrounds/mine.jpg"
printf 'extra\n' >"$HOME/.config/omarchy/backgrounds/mine/extra.jpg"
printf 'stock\n' >"$OMARCHY_PATH/themes/stock/backgrounds/stock.jpg"
printf 'live\n' >"$HOME/.config/omarchy/themes/mine/backgrounds/live.jpg"
ln -s "$HOME/.config/omarchy/themes/mine/backgrounds/live.jpg" \
  "$HOME/.local/state/omarchy/current/background"
mkdir -p "$HOME/.config/omarchy/themes/escape"
ln -s /tmp "$HOME/.config/omarchy/themes/escape/backgrounds"

mine=$HOME/.config/omarchy/themes/mine/backgrounds/mine.jpg
extra=$HOME/.config/omarchy/backgrounds/mine/extra.jpg
stock=$OMARCHY_PATH/themes/stock/backgrounds/stock.jpg
live=$HOME/.config/omarchy/themes/mine/backgrounds/live.jpg

out=$("$bg" copy mine "$mine" other)
echo "$out" | jq -e '.ok == true and (.path | endswith("/other/backgrounds/mine.jpg"))' >/dev/null
[[ -f $HOME/.config/omarchy/themes/other/backgrounds/mine.jpg ]]
[[ -f $mine ]]

out=$("$bg" copy stock "$stock" mine)
echo "$out" | jq -e '.ok == true and (.path | endswith("/mine/backgrounds/stock.jpg"))' >/dev/null
[[ -f $OMARCHY_PATH/themes/stock/backgrounds/stock.jpg ]]

out=$("$bg" copy stock "$stock" stock)
echo "$out" | jq -e '.ok == true and (.path | test("/\\.config/omarchy/backgrounds/stock/stock\\.jpg$"))' >/dev/null
[[ -f $HOME/.config/omarchy/backgrounds/stock/stock.jpg ]]
[[ -f $stock ]]

if "$bg" delete stock "$stock" >"$fake/stock-del.json" 2>/dev/null; then
  echo "deleted stock wallpaper" >&2
  exit 1
fi
jq -e '.error == "not-owned"' >/dev/null <"$fake/stock-del.json"
[[ -f $stock ]]

if "$bg" move stock "$stock" mine >"$fake/stock-move.json" 2>/dev/null; then
  echo "moved stock wallpaper" >&2
  exit 1
fi
jq -e '.error == "not-owned"' >/dev/null <"$fake/stock-move.json"
[[ -f $stock ]]
[[ ! -e $HOME/.config/omarchy/themes/mine/backgrounds/stock-2.jpg ]]

if "$bg" delete mine "$live" >"$fake/live.json" 2>/dev/null; then
  echo "deleted live wallpaper" >&2
  exit 1
fi
jq -e '.error == "current"' >/dev/null <"$fake/live.json"
[[ -f $live ]]

out=$("$bg" move mine "$live" other)
echo "$out" | jq -e '.ok == true and (.path | endswith("/other/backgrounds/live.jpg"))' >/dev/null
[[ ! -e $live ]]
target=$(readlink "$HOME/.local/state/omarchy/current/background")
[[ $target == "$HOME/.config/omarchy/themes/other/backgrounds/live.jpg" ]]

out=$("$bg" move mine "$extra" other)
echo "$out" | jq -e '.ok == true and (.path | endswith("/other/backgrounds/extra.jpg"))' >/dev/null
[[ ! -e $extra ]]
[[ -f $HOME/.config/omarchy/themes/other/backgrounds/extra.jpg ]]

out=$("$bg" delete mine "$mine")
echo "$out" | jq -e '.ok == true' >/dev/null
[[ ! -e $mine ]]

if "$bg" copy stock "$stock" escape >"$fake/escape.json" 2>/dev/null; then
  echo "wrote through escaped backgrounds dir" >&2
  exit 1
fi
jq -e '.error == "dest"' >/dev/null <"$fake/escape.json"
[[ ! -e /tmp/stock.jpg ]]

printf 'toml\n' >"$HOME/.config/omarchy/themes/mine/colors.toml"
if "$bg" delete mine "$HOME/.config/omarchy/themes/mine/colors.toml" >"$fake/toml.json" 2>/dev/null; then
  echo "deleted non-background" >&2
  exit 1
fi
jq -e '.error == "not-owned"' >/dev/null <"$fake/toml.json"
[[ -f $HOME/.config/omarchy/themes/mine/colors.toml ]]

if "$bg" copy '../x' "$stock" mine >"$fake/bad.json" 2>/dev/null; then
  echo "bad slug copied" >&2
  exit 1
fi
jq -e '.error == "invalid-slug"' >/dev/null <"$fake/bad.json"

echo "background ok"
