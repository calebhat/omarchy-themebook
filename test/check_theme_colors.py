#!/usr/bin/env python3
"""Check actual plugin palette bindings in an isolated Wayland/Quickshell session.

The catalog and picker are instantiated without opening them or starting the service.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


QML = r'''import QtQuick
import Quickshell
import qs.Commons as Theme
ShellRoot {
  id: testRoot
  property var objects: []
  Component.onCompleted: {
    // Load the selected theme before checking, rather than the singleton's defaults.
    Theme.Color.loadColors(PALETTE_JSON)
    Theme.Color.loadShell(SHELL_JSON)
    Theme.Color.loadUserShell(USER_SHELL_JSON)
    Qt.callLater(run)
  }
  function run() {
    var files = FILES
    var passed = 0, failures = []
    for (var i = 0; i < files.length; i++) {
      var file = files[i], name = file.slice(file.lastIndexOf('/') + 1)
      var component = Qt.createComponent(file)
      if (component.status !== Component.Ready) {
        failures.push(name + ': ' + component.errorString()); continue
      }
      var object = component.createObject(testRoot)
      if (!object) { failures.push(name + ': could not instantiate'); continue }
      objects.push(object)
      var checks = name === 'ThemeBook.qml' ? {
        fg: Theme.Color.foreground, bg: Theme.Color.background,
        accent: Theme.Color.accent, muted: Theme.Util.alpha(Theme.Color.foreground, 0.62)
      } : {
        dimColor: Theme.Color.background, foreground: Theme.Color.imagePicker.text,
        scrim: Theme.Color.imagePicker.scrim ?? "transparent", selectedBorder: Theme.Color.imagePicker.selectedBorder,
        unselectedBorder: Theme.Color.imagePicker.unselectedBorder
      }
      var ok = true
      for (var property in checks) {
        if (!Qt.colorEqual(object[property], checks[property])) {
          failures.push(name + '.' + property + ': expected ' + checks[property] + ', got ' + object[property]); ok = false
        }
      }
      if (ok) passed++
      component.destroy()
    }
    console.log('THEMEBOOK_COLOR_TESTS ' + JSON.stringify({passed:passed, failures:failures, background:String(Theme.Color.background), foreground:String(Theme.Color.foreground)}))
    Qt.quit()
  }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugin-dir', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if os.environ.get('WAYLAND_DISPLAY', '') in ('', 'omabox-guard'):
        parser.error('Run inside an isolated Wayland session')
    names = ('ThemeBook.qml', 'ThemePicker.qml')
    files = [(args.plugin_dir.resolve() / name).as_uri() for name in names]
    shell = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy')) / 'shell'
    with tempfile.TemporaryDirectory(prefix='themebook-colors-') as directory:
        root = Path(directory)
        imports = root / 'imports'
        imports.mkdir()
        (imports / 'qs').symlink_to(shell, target_is_directory=True)
        config = root / 'shell.qml'
        theme = Path.home() / '.local/state/omarchy/current/theme'
        user_shell = Path.home() / '.config/omarchy/shell.toml'
        source = QML.replace('FILES', json.dumps(files))
        source = source.replace('PALETTE_JSON', json.dumps((theme / 'colors.toml').read_text()))
        source = source.replace('USER_SHELL_JSON', json.dumps(user_shell.read_text() if user_shell.exists() else ''))
        source = source.replace('SHELL_JSON', json.dumps((theme / 'shell.toml').read_text() if (theme / 'shell.toml').exists() else ''))
        config.write_text(source)
        env = dict(os.environ, QML_IMPORT_PATH=str(imports), QT_QPA_PLATFORM='wayland',
                   QT_QPA_PLATFORMTHEME='basic', QT_QUICK_BACKEND='software')
        try:
            result = subprocess.run(['qs', '--no-color', '-p', str(config)], env=env,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        except subprocess.TimeoutExpired as error:
            print((error.stdout or b'').decode('utf-8', 'replace'))
            print('Theme-color check timed out')
            return 1
        print(result.stdout, end='')
        match = re.search(r'THEMEBOOK_COLOR_TESTS (\{[^\n]+\})', result.stdout)
        report = json.loads(match[1]) if match else {}
        return 0 if result.returncode == 0 and report.get('passed') == len(names) and report.get('failures') == [] else 1


if __name__ == '__main__':
    raise SystemExit(main())
