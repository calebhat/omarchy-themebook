#!/bin/bash
# Fail if the panel is missing a labeled control from the product spec.

set -euo pipefail
qml=$(cd "$(dirname "$0")/.." && pwd)/ThemeBook.qml
need=(
  'label: "All"'
  'label: "Favorites"'
  'label: "User"'
  'label: "Stock"'
  'label: "Light"'
  'label: "Dark"'
  'label: "Hidden"'
  'label: "Favorite"'
  'label: "Hide"'
  'label: "Move to folder"'
  'label: "Edit in Aether"'
  'label: "Random favorite"'
  'label: "Update git themes"'
  'label: "Remove"'
  'label: "Apply theme"'
  'label: "Sunrise / sunset"'
  'F Favorite   H Hide   Shift+↑/↓ Sort in folder'
  'onAccepted: root.submitPrompt()'
  'if (root.folderMenuOpen || root.promptKind || root.confirmRemove) return'
)
for s in "${need[@]}"; do
  if ! grep -F -q -- "$s" "$qml"; then
    echo "missing: $s" >&2
    exit 1
  fi
done
echo "labels ok"
