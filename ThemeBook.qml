pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var service: null
  property var manifest: null
  property bool closingFromHost: false
  property string selectedSlug: ""
  property string promptKind: ""
  property string promptFolderId: ""
  property string promptText: ""
  property bool folderMenuOpen: false
  property bool confirmRemove: false

  readonly property var svc: service
  readonly property var themes: svc ? svc.themes : []
  readonly property var rows: svc ? svc.rows : []
  readonly property var config: svc ? svc.config : Model.defaultConfig()
  readonly property var selected: {
    if (!svc || !selectedSlug) return null
    return Model.themeBySlug(svc.themes, selectedSlug)
  }
  readonly property var folderChoices: {
    var out = [{ id: "", name: "Ungrouped" }]
    var folders = root.config.folders || []
    for (var i = 0; i < folders.length; i++) out.push(folders[i])
    return out
  }
  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color accent: Color.accent
  readonly property color muted: Util.alpha(Color.foreground, 0.62)
  readonly property string fontFamily: Style.font.family
  readonly property bool opened: window.visible

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    if (svc) {
      svc.reloadCatalog()
      if (!selectedSlug && svc.currentSlug) selectedSlug = svc.currentSlug
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("io.github.calebhat.themebook")
    else window.visible = false
  }

  function selectOffset(delta) {
    var list = rows
    if (!list.length) return
    var idx = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].rowType === "theme" && list[i].slug === selectedSlug) { idx = i; break }
    }
    var j = idx
    while (true) {
      j += delta
      if (j < 0 || j >= list.length) return
      if (list[j].rowType === "theme") {
        selectedSlug = list[j].slug
        Qt.callLater(function() { root.revealSelected() })
        return
      }
    }
  }

  function selectedSection() {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].rowType === "theme" && rows[i].slug === selectedSlug) return rows[i].section
    }
    return ""
  }

  function applySelected() {
    if (root.folderMenuOpen || root.promptKind || root.confirmRemove) return
    if (selected && svc) svc.applyTheme(selected.slug)
  }

  function submitPrompt() {
    if (!svc || !root.promptKind) return
    if (root.promptKind === "folder") svc.createFolder(root.promptText || "Folder")
    if (root.promptKind === "rename") svc.renameFolder(root.promptFolderId, root.promptText)
    root.promptKind = ""
    keyCatcher.forceActiveFocus()
  }

  function cancelPrompt() {
    root.promptKind = ""
    keyCatcher.forceActiveFocus()
  }

  function colorKeys() {
    return ["accent", "background", "foreground", "red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
  }

  function colorFor(hex) {
    var s = String(hex || "")
    if (!/^#?[0-9a-fA-F]{3}([0-9a-fA-F]{3})?([0-9a-fA-F]{2})?$/.test(s)) return "transparent"
    return s
  }

  function revealSelected() {
    if (!themeList) return
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].rowType === "theme" && rows[i].slug === selectedSlug) {
        themeList.positionViewAtIndex(i, ListView.Visible)
        return
      }
    }
  }

  onSelectedSlugChanged: { /* user navigation calls revealSelected() */ }

  FloatingWindow {
    id: window
    title: "ThemeBook"
    color: root.bg
    implicitWidth: 1040
    implicitHeight: 760
    minimumSize: Qt.size(820, 560)
    visible: false

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("io.github.calebhat.themebook")
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (root.confirmRemove) {
          if (confirmDialog.handleKey(event)) event.accepted = true
          return
        }
        if (root.promptKind) {
          if (event.key === Qt.Key_Escape) { root.cancelPrompt(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submitPrompt()
            event.accepted = true
          }
          return
        }
        if (root.folderMenuOpen) {
          if (event.key === Qt.Key_Escape) { root.folderMenuOpen = false; event.accepted = true }
          return
        }
        if (searchField.activeFocus && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Down && event.key !== Qt.Key_Up) {
          return
        }
        if (searchField.activeFocus && event.key === Qt.Key_Escape) {
          searchField.focus = false
          keyCatcher.forceActiveFocus()
          event.accepted = true
          return
        }
        var shift = event.modifiers & Qt.ShiftModifier
        if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true }
        else if (event.key === Qt.Key_Slash) { searchField.forceActiveFocus(); event.accepted = true }
        else if (shift && (event.key === Qt.Key_Up || event.key === Qt.Key_K)) {
          if (svc && selectedSlug) svc.reorder(root.selectedSection(), selectedSlug, -1)
          event.accepted = true
        }
        else if (shift && (event.key === Qt.Key_Down || event.key === Qt.Key_J)) {
          if (svc && selectedSlug) svc.reorder(root.selectedSection(), selectedSlug, 1)
          event.accepted = true
        }
        else if (shift && event.key === Qt.Key_Left) {
          if (svc) svc.moveFolder(root.selectedSection(), -1)
          event.accepted = true
        }
        else if (shift && event.key === Qt.Key_Right) {
          if (svc) svc.moveFolder(root.selectedSection(), 1)
          event.accepted = true
        }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) { root.selectOffset(1); event.accepted = true }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) { root.selectOffset(-1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.applySelected(); event.accepted = true }
        else if (event.key === Qt.Key_F) { if (svc && selectedSlug) svc.toggleFavorite(selectedSlug); event.accepted = true }
        else if (event.key === Qt.Key_H) { if (svc && selectedSlug) svc.toggleHidden(selectedSlug); event.accepted = true }
        else if (event.key === Qt.Key_E) { if (svc && root.selected) svc.openAether(root.selected); event.accepted = true }
        else if (event.key === Qt.Key_N) {
          root.promptKind = "folder"
          root.promptText = ""
          event.accepted = true
        }
        else if (event.key === Qt.Key_R) {
          if (svc) svc.randomFavorite()
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            text: "ThemeBook"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search themes"
            focus: false
            color: root.fg
            font.family: root.fontFamily
            background: Rectangle {
              color: Util.alpha(root.fg, 0.06)
              radius: Style.cornerRadius
              border.width: 1
              border.color: Util.alpha(root.fg, 0.12)
            }
            onTextChanged: if (svc) svc.query = text
            Keys.onEscapePressed: {
              focus = false
              keyCatcher.forceActiveFocus()
            }
          }

          Text {
            text: svc && svc.currentSlug ? ("Current: " + (Model.themeBySlug(root.themes, svc.currentSlug) || { name: svc.currentSlug }).name) : ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Row {
          spacing: Style.space(6)
          Repeater {
            model: [
              { id: "all", label: "All" },
              { id: "favorites", label: "Favorites" },
              { id: "user", label: "User" },
              { id: "stock", label: "Stock" },
              { id: "light", label: "Light" },
              { id: "dark", label: "Dark" },
              { id: "hidden", label: "Hidden" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: chipText.implicitWidth + Style.space(16)
              height: Style.space(26)
              radius: height / 2
              color: (svc && svc.filter === modelData.id) ? Util.alpha(root.accent, 0.22) : Util.alpha(root.fg, 0.06)
              border.width: 1
              border.color: (svc && svc.filter === modelData.id) ? root.accent : Util.alpha(root.fg, 0.12)

              Text {
                id: chipText
                anchors.centerIn: parent
                text: modelData.label
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (svc) svc.filter = modelData.id
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(12)

          ListView {
            id: themeList
            Layout.preferredWidth: 380
            Layout.fillHeight: true
            clip: true
            model: root.rows
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
              required property var modelData
              width: themeList.width
              height: modelData.rowType === "header" ? Style.space(32) : Style.space(64)

              Row {
                visible: modelData.rowType === "header"
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)
                Text {
                  text: {
                    if (modelData.id === "favorites" && root.config.favorites.length === 0)
                      return "Favorites (none yet)"
                    return modelData.title || ""
                  }
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  opacity: 0.85
                }
                Text {
                  visible: !Model.isReservedSection(modelData.id)
                  text: "Rename"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.promptKind = "rename"
                      root.promptFolderId = modelData.id
                      root.promptText = modelData.title || ""
                      promptField.text = root.promptText
                    }
                  }
                }
                Text {
                  visible: !Model.isReservedSection(modelData.id)
                  text: "Delete"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (svc) svc.deleteFolder(modelData.id)
                  }
                }
              }

              Rectangle {
                visible: modelData.rowType === "theme"
                anchors.fill: parent
                radius: Style.cornerRadius
                color: modelData.slug === root.selectedSlug ? Util.alpha(root.accent, 0.16) : "transparent"
                border.width: modelData.current === true ? 1 : 0
                border.color: root.accent

                Row {
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(72)
                    height: parent.height
                    radius: Style.cornerRadius
                    clip: true
                    color: Util.alpha(root.fg, 0.06)
                    Image {
                      id: thumb
                      anchors.fill: parent
                      source: modelData.preview ? Util.fileUrl(modelData.preview) : ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      cache: true
                      sourceSize.width: 160
                      sourceSize.height: 100
                    }
                    Text {
                      visible: !modelData.preview || thumb.status === Image.Error
                      anchors.centerIn: parent
                      text: "—"
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(90)
                    spacing: 2
                    Text {
                      width: parent.width
                      text: (modelData.rowType === "theme" && root.config.favorites.indexOf(modelData.slug) >= 0 ? "★ " : "") + (modelData.name || modelData.slug || "")
                      elide: Text.ElideRight
                      color: modelData.current === true ? root.accent : root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: modelData.current === true
                    }
                    Text {
                      text: (modelData.source === "user" ? "User" : "Stock") + (modelData.mode ? " · " + modelData.mode : "")
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedSlug = modelData.slug
                  onDoubleClicked: if (svc) svc.applyTheme(modelData.slug)
                }
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.cornerRadius
            color: Util.alpha(root.fg, 0.04)
            border.width: 1
            border.color: Util.alpha(root.fg, 0.1)

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                radius: Style.cornerRadius
                clip: true
                color: Util.alpha(root.fg, 0.06)
                Image {
                  id: hero
                  anchors.fill: parent
                  source: root.selected && root.selected.preview ? Util.fileUrl(root.selected.preview) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  sourceSize.width: 960
                  sourceSize.height: 540
                }
                Text {
                  visible: !root.selected || !root.selected.preview || hero.status === Image.Error
                  anchors.centerIn: parent
                  text: !root.selected ? "Select a theme" : "No preview"
                  color: root.muted
                  font.family: root.fontFamily
                }
              }

              Text {
                text: root.selected ? root.selected.name : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                visible: !!root.selected
                text: {
                  if (!root.selected) return ""
                  var bits = [root.selected.source === "user" ? "User" : "Stock"]
                  if (root.selected.mode) bits.push(root.selected.mode)
                  if (root.selected.git) bits.push("git")
                  if (root.selected.current) bits.push("current")
                  return bits.join(" · ")
                }
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Row {
                spacing: Style.space(5)
                Repeater {
                  model: root.selected ? root.colorKeys() : []
                  delegate: Rectangle {
                    required property var modelData
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: 3
                    color: {
                      var hex = root.selected && root.selected.colors ? root.selected.colors[modelData] : ""
                      return root.colorFor(hex)
                    }
                    border.width: 1
                    border.color: Util.alpha(root.fg, 0.25)
                  }
                }
              }

              Text {
                visible: root.selected && root.selected.backgrounds && root.selected.backgrounds.length
                text: "Backgrounds"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                orientation: ListView.Horizontal
                clip: true
                spacing: Style.space(6)
                visible: root.selected && root.selected.backgrounds && root.selected.backgrounds.length
                model: root.selected && root.selected.backgrounds ? root.selected.backgrounds : []
                delegate: Rectangle {
                  required property var modelData
                  width: 96
                  height: 56
                  radius: Style.cornerRadius
                  clip: true
                  color: Util.alpha(root.fg, 0.06)
                  border.width: root.selected && root.selected.currentBackground === modelData ? 2 : 0
                  border.color: root.accent
                  Image {
                    anchors.fill: parent
                    source: Util.fileUrl(modelData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 192
                    sourceSize.height: 112
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (svc) svc.applyBackground(modelData)
                  }
                }
              }

              Flow {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Repeater {
                  model: [
                    { id: "fav", label: "Favorite" },
                    { id: "hide", label: "Hide" },
                    { id: "folder", label: "Move to folder" },
                    { id: "aether", label: "Edit in Aether" },
                    { id: "random", label: "Random favorite" },
                    { id: "update", label: "Update git themes" },
                    { id: "remove", label: "Remove" },
                    { id: "apply", label: "Apply theme" }
                  ]
                  delegate: Rectangle {
                    required property var modelData
                    visible: {
                      if (modelData.id === "aether") return !!(svc && svc.aetherAvailable && root.selected)
                      if (modelData.id === "update") return !!(root.selected && root.selected.git)
                      if (modelData.id === "remove") return !!(root.selected && root.selected.source === "user" && root.selected.slug !== (svc ? svc.currentSlug : ""))
                      if (modelData.id === "random") return true
                      return !!root.selected || modelData.id === "folder"
                    }
                    width: btnLabel.implicitWidth + Style.space(16)
                    height: Style.space(30)
                    radius: Style.cornerRadius
                    color: modelData.id === "apply" ? Util.alpha(root.accent, 0.28) : Util.alpha(root.fg, 0.08)
                    Text {
                      id: btnLabel
                      anchors.centerIn: parent
                      text: {
                        if (modelData.id === "fav" && root.config.favorites.indexOf(root.selectedSlug) >= 0)
                          return "Unfavorite"
                        if (modelData.id === "hide" && root.config.hidden.indexOf(root.selectedSlug) >= 0)
                          return "Unhide"
                        return modelData.label
                      }
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (!svc) return
                        if (modelData.id === "fav" && selectedSlug) svc.toggleFavorite(selectedSlug)
                        else if (modelData.id === "hide" && selectedSlug) svc.toggleHidden(selectedSlug)
                        else if (modelData.id === "folder") root.folderMenuOpen = !root.folderMenuOpen
                        else if (modelData.id === "aether" && root.selected) svc.openAether(root.selected)
                        else if (modelData.id === "random") svc.randomFavorite()
                        else if (modelData.id === "update") svc.updateGitThemes()
                        else if (modelData.id === "remove") root.confirmRemove = true
                        else if (modelData.id === "apply") root.applySelected()
                      }
                    }
                  }
                }
              }

              Column {
                visible: root.folderMenuOpen
                spacing: Style.space(4)
                Text {
                  text: "Move to"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Repeater {
                  model: root.folderChoices
                  delegate: Text {
                    required property var modelData
                    text: "→ " + modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (svc && selectedSlug) svc.moveToFolder(selectedSlug, modelData.id)
                        root.folderMenuOpen = false
                      }
                    }
                  }
                }
                Text {
                  text: "+ New folder"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.folderMenuOpen = false
                      root.promptKind = "folder"
                      root.promptText = ""
                    }
                  }
                }
              }

              Item { Layout.fillHeight: true }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "Schedule"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: [
              { id: "off", label: "Off" },
              { id: "clock", label: "Clock" },
              { id: "sun", label: "Sunrise / sunset" }
            ]
            delegate: Rectangle {
              required property var modelData
              visible: modelData.id !== "sun" || (svc && svc.sunwaitAvailable)
              width: schedLabel.implicitWidth + Style.space(14)
              height: Style.space(24)
              radius: height / 2
              color: config.schedule.mode === modelData.id ? Util.alpha(root.accent, 0.22) : Util.alpha(root.fg, 0.06)
              Text {
                id: schedLabel
                anchors.centerIn: parent
                text: modelData.label
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                onClicked: if (svc) svc.setSchedule({ mode: modelData.id })
              }
            }
          }

          Text {
            visible: !!(svc && svc.otherSchedulerEnabled)
            text: "Another theme scheduler is enabled — ThemeBook stays off."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item { Layout.fillWidth: true }

          Text {
            visible: config.schedule.mode === "clock"
            text: "Day " + (config.schedule.dayAt || "") + "  −/+"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (svc) svc.bumpScheduleTime("day", mouse.button === Qt.RightButton ? -15 : 15)
              }
            }
          }
          Text {
            visible: config.schedule.mode === "clock"
            text: "Night " + (config.schedule.nightAt || "") + "  −/+"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (svc) svc.bumpScheduleTime("night", mouse.button === Qt.RightButton ? -15 : 15)
              }
            }
          }
        }

        Row {
          visible: config.schedule.mode !== "off" && !(svc && svc.otherSchedulerEnabled)
          spacing: Style.space(10)
          Text {
            text: "Day: " + (config.schedule.day === "__random_favorite__" ? "Random favorite" : (Model.themeBySlug(root.themes, config.schedule.day) || { name: config.schedule.day || "—" }).name)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              anchors.fill: parent
              onClicked: if (svc && selectedSlug) svc.setSchedule({ day: selectedSlug })
            }
          }
          Text {
            text: "Night: " + (config.schedule.night === "__random_favorite__" ? "Random favorite" : (Model.themeBySlug(root.themes, config.schedule.night) || { name: config.schedule.night || "—" }).name)
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            MouseArea {
              anchors.fill: parent
              onClicked: if (svc && selectedSlug) svc.setSchedule({ night: selectedSlug })
            }
          }
          Text {
            text: "Click a label to set the selected theme. Clock: left-click time +15m, right-click −15m."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          Layout.fillWidth: true
          text: "F Favorite   H Hide   Shift+↑/↓ Sort in folder   Shift+←/→ Sort folders   N New folder   Enter Apply   E Aether   R Random favorite   / Search   Esc Close"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Rectangle {
        visible: root.promptKind.length > 0
        anchors.fill: parent
        color: Util.alpha(root.bg, 0.72)
        onVisibleChanged: if (visible) Qt.callLater(function() { promptField.forceActiveFocus() })
        MouseArea { anchors.fill: parent; onClicked: root.cancelPrompt() }

        Rectangle {
          width: 380
          height: 168
          radius: Style.cornerRadius
          color: root.bg
          border.color: root.accent
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { /* keep dialog open */ } }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(10)
            Text {
              text: root.promptKind === "rename" ? "Rename folder" : "New folder"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }
            TextField {
              id: promptField
              width: 320
              text: root.promptText
              onTextChanged: root.promptText = text
              onAccepted: root.submitPrompt()
              Keys.onEscapePressed: root.cancelPrompt()
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: cancelLabel.implicitWidth + Style.space(16)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.08)
                Text {
                  id: cancelLabel
                  anchors.centerIn: parent
                  text: "Cancel"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.cancelPrompt() }
              }
              Rectangle {
                width: okLabel.implicitWidth + Style.space(16)
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.accent, 0.28)
                Text {
                  id: okLabel
                  anchors.centerIn: parent
                  text: root.promptKind === "rename" ? "Rename" : "Create"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea { anchors.fill: parent; onClicked: root.submitPrompt() }
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        opened: root.confirmRemove
        message: root.selected ? ("Remove user theme “" + root.selected.name + "”? This deletes that theme from your user themes folder.") : "Remove theme?"
        confirmText: "Remove"
        onCanceled: root.confirmRemove = false
        onConfirmed: {
          if (svc && selectedSlug) svc.removeTheme(selectedSlug)
          root.confirmRemove = false
        }
      }
    }
  }
}
