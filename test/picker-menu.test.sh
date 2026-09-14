#!/bin/bash
# User menu override for Style > Theme is added and removed cleanly.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
export HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/.config/omarchy/extensions"
printf '%s\n' '{
  "style.themebook": {"label":"ThemeBook","action":"x"},
  "style.theme": {"action":"omarchy-shell shell summon io.github.calebhat.themebook picker"}
}' >"$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

"$root/scripts/set-default-picker" restore
if grep -q '"style.theme"' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  echo "restore left a style.theme override" >&2
  cat "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" >&2
  exit 1
fi
if ! grep -q '"style.themebook"' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  echo "restore removed ThemeBook row" >&2
  exit 1
fi

"$root/scripts/set-default-picker" replace
if ! grep -q 'omarchy-shell themebook pick' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  echo "replace did not install pick action" >&2
  exit 1
fi
if ! grep -q 'omarchy-theme-switcher' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  echo "replace did not install stock-picker fallback" >&2
  exit 1
fi
"$root/scripts/set-default-picker" replace
count=$(grep -c '"style.theme"' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" || true)
if (( count != 1 )); then
  echo "replace duplicated style.theme ($count)" >&2
  exit 1
fi
"$root/scripts/set-default-picker" restore
if grep -q '"style.theme"' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  echo "second restore failed" >&2
  exit 1
fi

# Unload path: python3 -c (same as Service.restoreMenuPy) after the plugin
# checkout is gone, so disable/remove cannot depend on scripts/set-default-picker.
"$root/scripts/set-default-picker" replace
py=$(sed -n 's/.*readonly property string restoreMenuPy: "\(.*\)"/\1/p' "$root/Service.qml" | tail -n1)
[[ -n $py ]] || { echo "could not extract restoreMenuPy" >&2; exit 1; }
python3 -c "$(printf '%b' "$py")" "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if grep -q '"style.theme"' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  echo "unload python restore left a style.theme override" >&2
  cat "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" >&2
  exit 1
fi
if ! grep -q '"style.themebook"' "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  echo "unload python restore removed ThemeBook row" >&2
  exit 1
fi
echo "picker-menu ok"
