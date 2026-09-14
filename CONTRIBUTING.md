# Contributing

Source of truth: this repository, installed as a normal Omarchy plugin.
Display name is **ThemeBook**; plugin id is `io.github.calebhat.themebook`.

```bash
omarchy plugin add https://github.com/calebhat/omarchy-themebook.git --enable
omarchy plugin validate ~/.config/omarchy/plugins/io.github.calebhat.themebook
```

On this machine, development can live in `~/Work/omarchy-themebook` and deploy with rsync (plugin folders must not contain symlinks):

```bash
rsync -a --delete --exclude .git --exclude .gitignore \
  ~/Work/omarchy-themebook/ \
  ~/.config/omarchy/plugins/io.github.calebhat.themebook/
omarchy restart shell
```

Do not keep a second copy inside private dotfiles.

Commit as `calebhat <97716470+calebhat@users.noreply.github.com>`.

Marketplace: one `[Plugin]: ThemeBook` issue. Edit that issue to revalidate. Do not open a duplicate.

Do not auto-insert a Style > ThemeBook row in `omarchy-menu.jsonc`. Theme menu may override `style.theme` only while that checkbox is on, and must strip that override when the checkbox is off or the service unloads. The Apps launcher is created only when that desktop file is missing.
