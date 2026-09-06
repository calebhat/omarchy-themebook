#!/bin/bash
# Fail if the panel is missing a labeled control from the product spec.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
qml=$root/ThemeBook.qml
picker=$root/ThemePicker.qml
need=(
  'label: "All"'
  'label: "Favorites"'
  'label: "User"'
  'label: "Stock"'
  'label: "Light"'
  'label: "Dark"'
  'label: "Hidden"'
  'label: "Move to folder"'
  'label: "Favorite"'
  'label: "Edit in Aether"'
  'label: "Hide"'
  'label: "Show"'
  'text: "Add themes"'
  'Accessible.name: "Remove from folder"'
  'text: "Check to add. Uncheck to remove.'
  'text: "Save folder"'
  'text: "Save folders"'
  'label: "Random favorite"'
  'label: "Update git themes"'
  'label: "Delete from OS"'
  'label: "Apply theme"'
  'label: "Sunrise / sunset"'
  'label: "Timed Themes"'
  'text: "Wallpapers"'
  'text: "Apply and stop schedule"'
  'text: "New folder"'
  'id: folderActPopup'
  'folderActMenuOpensUp'
  '{ id: "rename", label: "Rename" }'
  '{ id: "delete", label: "Delete" }'
  'text: "Collapse all"'
  'text: "Expand all"'
  'text: "Theme menu"'
  'text: "Picker"'
  'label: "Theme cycle"'
  'label: "Wallpaper cycle"'
  'id: scheduleOnBadge'
  'id: themeListCol'
  'text: "Also cycle wallpapers"'
  'text: "Backgrounds — click to preview here. Star one as default for apply and picker."'
  'text: "Copy palette"'
  'Click a color to copy its hex'
  '["wl-copy", "--", value]'
  'Choose folder…'
  'text: rule && Model.hourIsPm(rule.time) ? "PM" : "AM"'
  'text: "Delete folder'
  'F Favorite   H Hide   U Update git   Del Delete from OS   Shift+↑/↓ Sort in folder'
  'Esc catalog   Tab mode   C 12/24   ↑/↓ row   ←/→ field   Enter activate   A add time'
  'onAccepted: root.submitPrompt()'
  'if (root.folderMenuOpen || root.promptKind || root.confirmRemove) return'
)
for s in "${need[@]}"; do
  if ! grep -F -q -- "$s" "$qml"; then
    echo "missing: $s" >&2
    exit 1
  fi
done
if ! grep -F -q -- "type to filter" "$picker"; then
  echo "missing: footer shortcuts in ThemePicker" >&2
  exit 1
fi
if ! grep -F -q -- "folderFilter" "$picker"; then
  echo "missing: independent folder filter" >&2
  exit 1
fi
if ! grep -F -q -- "themeFilter" "$picker"; then
  echo "missing: independent theme filter" >&2
  exit 1
fi
if ! grep -F -q -- "rememberLocation" "$picker"; then
  echo "missing: persistent picker location" >&2
  exit 1
fi
if ! grep -F -q -- "function keyText" "$picker"; then
  echo "missing: keyText fallback for filter typing" >&2
  exit 1
fi
if grep -F -q -- 'title: "ThemeBook Picker"' "$qml"; then
  echo "old picker window still present" >&2
  exit 1
fi
if [[ $(grep -c -- 'onSelectedSlugChanged' "$qml") -ne 1 ]]; then
  echo "duplicate onSelectedSlugChanged (QML will refuse to load the catalog)" >&2
  exit 1
fi
if ! grep -F -q -- 'function togglePicker()' "$root/Service.qml"; then
  echo "missing: picker toggle so pick IPC can dismiss exclusive-focus overlay" >&2
  exit 1
fi
if ! grep -F -q -- 'scriptPath("remove")' "$root/Service.qml"; then
  echo "missing: OS delete uses scripts/remove" >&2
  exit 1
fi
if grep -F -q -- 'omarchy", "theme", "remove"' "$root/Service.qml"; then
  echo "OS delete still calls omarchy theme remove (misses extra wallpapers)" >&2
  exit 1
fi
if ! grep -F -q -- 'scriptPath("update-git")' "$root/Service.qml"; then
  echo "missing: git update uses scripts/update-git" >&2
  exit 1
fi
if grep -F -q -- 'omarchy", "theme", "update"' "$root/Service.qml"; then
  echo "git update still calls omarchy theme update with no progress" >&2
  exit 1
fi
if ! grep -F -q -- 'Updating git themes' "$qml"; then
  echo "missing: git update progress overlay" >&2
  exit 1
fi
if grep -E -q 'radius: (height / 2|[0-9]+)' "$qml" "$picker"; then
  echo "hardcoded radius; use Style.cornerRadius" >&2
  grep -nE 'radius: (height / 2|[0-9]+)' "$qml" "$picker" >&2
  exit 1
fi
echo "labels ok"
