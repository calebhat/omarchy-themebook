#!/bin/bash
# Existing Apps launchers must get StartupNotify=false without a full replace.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
export HOME=$fake

plugin=$fake/.config/omarchy/plugins/io.github.calebhat.themebook
mkdir -p "$plugin/share/applications" "$fake/.local/share/applications"
cp "$root/share/applications/io.github.calebhat.themebook.desktop" "$plugin/share/applications/"
cp "$root/icon.png" "$plugin/icon.png"

dst=$fake/.local/share/applications/io.github.calebhat.themebook.desktop
cat >"$dst" <<'EOF'
[Desktop Entry]
Type=Application
Name=ThemeBook
Exec=omarchy-shell shell toggle io.github.calebhat.themebook '{}'
TryExec=omarchy-shell
Terminal=false
EOF

"$root/scripts/desktop-entry" "$plugin"
grep -qx 'StartupNotify=false' "$dst"
grep -qx 'Name=ThemeBook' "$dst"
grep -qx 'Icon=io.github.calebhat.themebook' "$dst"
count=$(grep -c '^StartupNotify=' "$dst")
(( count == 1 ))
[[ -f $fake/.local/share/icons/hicolor/48x48/apps/io.github.calebhat.themebook.png ]]
[[ -f $fake/.local/share/icons/hicolor/512x512/apps/io.github.calebhat.themebook.png ]]

"$root/scripts/desktop-entry" "$plugin"
count=$(grep -c '^StartupNotify=' "$dst")
(( count == 1 ))
echo "desktop-entry ok"
