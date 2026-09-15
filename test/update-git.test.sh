#!/bin/bash
# Isolated git-check helper: empty, skip symlink, current, available, no checkout, no hooks.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
update=$root/scripts/update-git
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
export HOME=$fake/home
export THEMEBOOK_UPDATE_WRAPPED=1
mkdir -p "$HOME/.config/omarchy/themes"

if grep -E '^[^#]*\b(pull|merge|checkout|reset|rebase)\b' "$update"; then
  echo "update-git still applies remote content" >&2
  exit 1
fi

lines=$("$update")
echo "$lines" | jq -s -e '.[0].event == "start" and .[0].total == 0 and .[-1].event == "done"' >/dev/null

export GIT_CONFIG_GLOBAL=$fake/gitconfig
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" user.email "themebook@test"
git config --file "$GIT_CONFIG_GLOBAL" user.name "ThemeBook"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

remote=$fake/remote.git
git init --bare "$remote" >/dev/null
work=$fake/work
git clone "$remote" "$work" >/dev/null 2>&1
git -C "$work" -c user.email=themebook@test -c user.name=ThemeBook commit --allow-empty -m init >/dev/null
git -C "$work" push -u origin HEAD >/dev/null 2>&1
first=$(git -C "$work" rev-parse HEAD)

clone=$HOME/.config/omarchy/themes/forest-night
git clone "$remote" "$clone" >/dev/null 2>&1
printf 'keep\n' >"$clone/colors.toml"

ln -s "$clone" "$HOME/.config/omarchy/themes/as-link"

broken=$HOME/.config/omarchy/themes/broken-git
mkdir -p "$broken/.git"

evil=$HOME/.config/omarchy/themes/evil-origin
git clone "$remote" "$evil" >/dev/null 2>&1
git -C "$evil" remote set-url origin 'ext::sh -c id'

fileorig=$HOME/.config/omarchy/themes/file-origin
git clone "$remote" "$fileorig" >/dev/null 2>&1
git -C "$fileorig" remote set-url origin "file://$remote"

lines=$("$update" || true)
echo "$lines" | jq -s -e 'map(select(.event=="start"))[0].total == 4' >/dev/null
echo "$lines" | jq -s -e 'any(.[]; .event=="theme" and .slug=="forest-night" and .status=="current")' >/dev/null
echo "$lines" | jq -s -e 'any(.[]; .event=="theme" and .slug=="broken-git" and .status=="failed")' >/dev/null
echo "$lines" | jq -s -e 'any(.[]; .event=="theme" and .slug=="evil-origin" and .status=="failed")' >/dev/null
echo "$lines" | jq -s -e 'any(.[]; .event=="theme" and .slug=="file-origin" and .status=="failed")' >/dev/null
echo "$lines" | jq -s -e 'all(.[]; .slug != "as-link")' >/dev/null
echo "$lines" | jq -s -e '.[-1].event == "done"' >/dev/null
[[ $(git -C "$clone" rev-parse HEAD) == $first ]]
[[ $(cat "$clone/colors.toml") == keep ]]

git -C "$work" -c user.email=themebook@test -c user.name=ThemeBook commit --allow-empty -m two >/dev/null
git -C "$work" push >/dev/null 2>&1
second=$(git -C "$work" rev-parse HEAD)

mkdir -p "$clone/.git/hooks"
printf '#!/bin/bash\necho fired >%q\n' "$fake/hook-fired" >"$clone/.git/hooks/reference-transaction"
chmod +x "$clone/.git/hooks/reference-transaction"

lines=$("$update" || true)
echo "$lines" | jq -s -e 'any(.[]; .event=="theme" and .slug=="forest-night" and .status=="available")' >/dev/null
[[ $(git -C "$clone" rev-parse HEAD) == $first ]]
[[ $second != $first ]]
[[ $(cat "$clone/colors.toml") == keep ]]
[[ ! -e $fake/hook-fired ]]
echo "update-git ok"
