#!/bin/bash
# Isolated git-update helper: empty, skip symlink, already-current clone, fail.

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
update=$root/scripts/update-git
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
export HOME=$fake/home
export THEMEBOOK_UPDATE_WRAPPED=1
mkdir -p "$HOME/.config/omarchy/themes"

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

clone=$HOME/.config/omarchy/themes/forest-night
git clone "$remote" "$clone" >/dev/null 2>&1

ln -s "$clone" "$HOME/.config/omarchy/themes/as-link"

broken=$HOME/.config/omarchy/themes/broken-git
mkdir -p "$broken/.git"
# not a real repo; git pull fails

lines=$("$update" || true)
echo "$lines" | jq -s -e 'map(select(.event=="start"))[0].total == 2' >/dev/null
echo "$lines" | jq -s -e 'any(.[]; .event=="theme" and .slug=="forest-night" and (.status=="current" or .status=="updated"))' >/dev/null
echo "$lines" | jq -s -e 'any(.[]; .event=="theme" and .slug=="broken-git" and .status=="failed")' >/dev/null
echo "$lines" | jq -s -e 'all(.[]; .slug != "as-link")' >/dev/null
echo "$lines" | jq -s -e '.[-1].event == "done"' >/dev/null
echo "update-git ok"
