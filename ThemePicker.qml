pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var service: null
  property bool opened: false
  property int selectedIndex: 0
  property int folderIndex: 0
  property string folderId: "all"
  property string focusRow: "themes"
  property string folderFilter: ""
  property string themeFilter: ""
  property var imageArray: []
  property bool layoutSettled: false

  readonly property color dimColor: Color.background
  readonly property color foreground: Color.imagePicker.text
  readonly property color scrim: Color.imagePicker.scrim
  readonly property color selectedBorder: Color.imagePicker.selectedBorder
  readonly property color unselectedBorder: Color.imagePicker.unselectedBorder
  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  property int bottomChromeHeight: 72
  property int folderRowHeight: 96

  readonly property var folderTabs: {
    var tabs = [{ id: "all", name: "All", themes: [] }]
    if (!service) return tabs
    var secs = Model.pickerSections(service.config, service.themes)
    for (var i = 0; i < secs.length; i++) tabs.push(secs[i])
    return tabs
  }

  function previewFor(theme) {
    if (!theme) return ""
    var def = Model.defaultWallpaper(root.service ? root.service.config : {}, theme)
    return def || theme.preview || ""
  }

  function folderMatches(index) {
    var tabs = folderTabs
    if (index < 0 || index >= tabs.length) return false
    if (!folderFilter) return true
    return Model.fuzzyMatch(folderFilter, tabs[index].name, tabs[index].id)
  }

  function folderFilteredPos(index) {
    var pos = 0
    for (var i = 0; i < index; i++) if (folderMatches(i)) pos++
    return pos
  }

  function folderSelectedFilteredPos() {
    return folderFilteredPos(folderIndex)
  }

  function firstMatchingFolder() {
    var tabs = folderTabs
    for (var i = 0; i < tabs.length; i++) if (folderMatches(i)) return i
    return 0
  }

  function itemMatches(index) {
    var item = imageArray[index]
    if (!item) return false
    if (folderId !== "all") {
      var inFolder = false
      var tabs = folderTabs
      for (var i = 0; i < tabs.length; i++) {
        if (tabs[i].id !== folderId) continue
        var slugs = tabs[i].themes || []
        for (var j = 0; j < slugs.length; j++)
          if (slugs[j] === item.slug) { inFolder = true; break }
      }
      if (!inFolder) return false
    }
    if (themeFilter) return Model.fuzzyMatch(themeFilter, item.name, item.slug)
    return true
  }

  function filteredPosition(index) {
    var pos = 0
    for (var i = 0; i < index; i++) if (itemMatches(i)) pos++
    return pos
  }

  function selectedFilteredPosition() {
    return filteredPosition(selectedIndex)
  }

  function firstMatch() {
    for (var i = 0; i < imageArray.length; i++) if (itemMatches(i)) return i
    return 0
  }

  function rebuild() {
    if (!service) return
    var themes = service.themes || []
    var arr = []
    var current = service.currentSlug || ""
    var sel = 0
    for (var i = 0; i < themes.length; i++) {
      var t = themes[i]
      var prev = root.previewFor(t)
      var thumb = t.thumbnail || ""
      // Full-res wallpapers (e.g. 7k PNG) freeze the carousel. Only show
      // warmed JPEGs or ThemeBook swatches until thumbs exist.
      if (thumb.indexOf("/omarchy/image-selector/") < 0 && thumb.indexOf("/omarchy/themebook/swatches/") < 0)
        thumb = ""
      arr.push({
        filePath: prev,
        fileName: t.slug,
        thumbnailPath: thumb,
        slug: t.slug,
        name: t.name || t.slug
      })
      if (t.slug === current) sel = i
    }
    imageArray = arr
    selectedIndex = sel
    if (!itemMatches(selectedIndex)) selectedIndex = firstMatch()
    layoutSettled = true
  }

  function restoreSelection(slug) {
    if (!slug) return
    for (var i = 0; i < imageArray.length; i++) {
      if (imageArray[i].slug === slug) {
        selectedIndex = i
        if (!itemMatches(selectedIndex)) selectedIndex = firstMatch()
        return
      }
    }
  }

  function rememberLocation() {
    if (!service || typeof service.setPickerLocation !== "function") return
    var slug = ""
    if (imageArray[selectedIndex] && itemMatches(selectedIndex))
      slug = imageArray[selectedIndex].slug
    service.setPickerLocation(folderId, slug, focusRow)
  }

  function open() {
    if (service && (!service.themes || !service.themes.length))
      service.reloadCatalog()
    var p = service && service.config ? service.config.picker : null
    var def = p && p.defaultFolder ? p.defaultFolder : "all"
    folderId = (p && p.lastFolder) ? p.lastFolder : (def || "all")
    folderIndex = 0
    var foundFolder = false
    for (var i = 0; i < folderTabs.length; i++) {
      if (folderTabs[i].id === folderId) { folderIndex = i; foundFolder = true }
    }
    if (!foundFolder) {
      folderId = def || "all"
      folderIndex = 0
      for (var j = 0; j < folderTabs.length; j++) {
        if (folderTabs[j].id === folderId) folderIndex = j
      }
    }
    folderFilter = ""
    themeFilter = ""
    rebuild()
    restoreSelection(p && p.lastSlug ? p.lastSlug : "")
    opened = true
    focusRow = "themes"
    Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  property bool catalogOpen: false

  function close() {
    rememberLocation()
    opened = false
  }

  function select(index) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    if (index >= imageArray.length) index = imageArray.length - 1
    if (!itemMatches(index)) return
    selectedIndex = index
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0) return
    var index = selectedIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        selectedIndex = index
        return
      }
    }
  }

  function applySelected() {
    if (!service || imageArray.length === 0) return
    var item = imageArray[selectedIndex]
    if (!item || !item.slug) return
    // Close before apply so a heavy current wallpaper (theme-set snapshots
    // it on the shell GUI thread) cannot freeze the overlay in place.
    if (Model.isScheduleActive(service.config)) {
      service.requestManualApply(item.slug)
      return
    }
    var slug = item.slug
    close()
    Qt.callLater(function() {
      if (root.service) root.service.requestManualApply(slug)
    })
  }

  function setFolder(id) {
    folderId = id || "all"
    var tabs = folderTabs
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].id === folderId) folderIndex = i
    }
    if (!itemMatches(selectedIndex)) selectedIndex = firstMatch()
  }

  function setFolderByIndex(n) {
    var tabs = folderTabs
    if (tabs.length === 0) return
    var idx = n
    if (idx < 0) idx = tabs.length - 1
    if (idx >= tabs.length) idx = 0
    folderIndex = idx
    setFolder(tabs[idx].id)
  }

  function adjacentFolder(direction) {
    var tabs = folderTabs
    var count = tabs.length
    if (count === 0) return
    var index = folderIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (folderMatches(index)) {
        setFolder(tabs[index].id)
        return
      }
    }
  }

  function keyText(event) {
    if (event.text && event.text.length === 1) {
      var t = event.text
      if (t.charCodeAt(0) >= 32 && t.charCodeAt(0) !== 127) return t
    }
    var k = event.key
    if (k >= Qt.Key_A && k <= Qt.Key_Z) {
      var c = String.fromCharCode(97 + (k - Qt.Key_A))
      if (event.modifiers & Qt.ShiftModifier) c = c.toUpperCase()
      return c
    }
    if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(48 + (k - Qt.Key_0))
    if (k === Qt.Key_Space) return " "
    if (k === Qt.Key_Minus || k === Qt.Key_Underscore) return event.modifiers & Qt.ShiftModifier ? "_" : "-"
    if (k === Qt.Key_Period) return "."
    return ""
  }

  function currentFilter() {
    return focusRow === "folders" ? folderFilter : themeFilter
  }

  function setCurrentFilter(text) {
    if (focusRow === "folders") {
      folderFilter = text
      if (!folderMatches(folderIndex)) {
        var i = firstMatchingFolder()
        if (folderTabs[i]) setFolder(folderTabs[i].id)
      }
    } else {
      themeFilter = text
      if (!itemMatches(selectedIndex)) selectedIndex = firstMatch()
    }
  }

  function currentLabel() {
    if (!itemMatches(selectedIndex)) return "No themes in this folder"
    var item = imageArray[selectedIndex]
    return item ? item.name : ""
  }

  function footerText() {
    var tabs = folderTabs
    var parts = []
    for (var i = 0; i < tabs.length && i < 10; i++)
      parts.push(i + " " + tabs[i].name)
    parts.push("←/→ choose")
    parts.push("Enter apply")
    parts.push("Esc close")
    return parts.join("   ")
  }

  onOpenedChanged: {
    if (!opened) layoutSettled = false
    else Qt.callLater(function() { keyScope.forceActiveFocus() })
  }

  Connections {
    target: root.service
    function onCatalogRevisionChanged() {
      if (root.opened) root.rebuild()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      visible: root.opened
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      onClicked: root.close()
    }

    FocusScope {
      id: keyScope
      anchors.fill: parent
      visible: root.opened
      focus: true
      Keys.priority: Keys.BeforeItem
      Component.onCompleted: forceActiveFocus()
      Keys.onPressed: function(event) {
        if (root.service && root.service.pendingManualSlug) {
          if (event.key === Qt.Key_Escape) { root.service.cancelManualApply(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.service.confirmManualApply()
            root.close()
            event.accepted = true
          }
          return
        }
        if (event.key === Qt.Key_Escape) {
          if (root.currentFilter()) root.setCurrentFilter("")
          else root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.applySelected(); event.accepted = true }
        else if (event.key === Qt.Key_Up) {
          root.focusRow = "folders"
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.focusRow = "themes"
          event.accepted = true
        } else if (Util.editsFilter(event, root.currentFilter())) {
          root.setCurrentFilter(Util.editedFilter(event, root.currentFilter()))
          event.accepted = true
        } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
          if (root.focusRow === "folders") root.adjacentFolder(-1)
          else root.selectAdjacent(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
          if (root.focusRow === "folders") root.adjacentFolder(1)
          else root.selectAdjacent(1)
          event.accepted = true
        } else if ((event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier) && root.keyText(event).length === 1) {
          root.setCurrentFilter(root.currentFilter() + root.keyText(event))
          event.accepted = true
        }
      }

    Item {
      id: card
      visible: root.opened && root.layoutSettled
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
      height: root.expandedHeight + Style.space(30) + root.bottomChromeHeight + root.folderRowHeight
      anchors.centerIn: parent
      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: folderChrome
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(6)
        z: 200

        Text {
          textFormat: Text.PlainText
          visible: root.focusRow === "folders" || root.folderFilter.length > 0
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.folderFilter
          color: root.foreground
          opacity: 0.9
          style: Text.Outline
          styleColor: Util.alpha(root.dimColor, 0.7)
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }

        Item {
          id: folderStrip
          width: parent.width
          height: Style.space(40)
          clip: true

          Row {
            id: folderRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)
            x: {
              var cx = 0
              var cw = 0
              var kids = folderRow.children
              for (var i = 0; i < kids.length; i++) {
                var ch = kids[i]
                if (!ch || ch.current === undefined) continue
                if (ch.current) {
                  cx = ch.x
                  cw = ch.width
                  break
                }
              }
              return folderStrip.width / 2 - cx - cw / 2
            }
            Repeater {
              model: {
                var tabs = root.folderTabs
                var out = []
                for (var i = 0; i < tabs.length; i++)
                  if (root.folderMatches(i)) out.push(tabs[i])
                return out
              }
              delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool current: root.folderId === modelData.id
                readonly property bool rowFocus: root.focusRow === "folders"
                height: Style.space(36)
                width: Math.max(Style.space(88), folderLab.implicitWidth + Style.space(20))
                radius: Style.cornerRadius
                color: current
                  ? Util.alpha(Color.accent, rowFocus ? 0.42 : 0.22)
                  : Util.alpha(root.foreground, rowFocus ? 0.12 : 0.06)
                border.width: current && rowFocus ? 2 : 1
                border.color: current
                  ? Color.accent
                  : Util.alpha(root.foreground, rowFocus ? 0.28 : 0.12)
                Text {
                  textFormat: Text.PlainText
                  id: folderLab
                  anchors.centerIn: parent
                  text: {
                    var n = modelData.id === "all"
                      ? (root.service && root.service.themes ? root.service.themes.length : 0)
                      : (modelData.themes ? modelData.themes.length : 0)
                    return modelData.name + " (" + n + ")"
                  }
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: current
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.focusRow = "folders"
                    root.setFolder(modelData.id)
                  }
                }
              }
            }
          }

          Rectangle {
            anchors.left: parent.left
            width: Style.space(56)
            height: parent.height
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: root.scrim }
              GradientStop { position: 1.0; color: "transparent" }
            }
          }
          Rectangle {
            anchors.right: parent.right
            width: Style.space(56)
            height: parent.height
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 1.0; color: root.scrim }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.focusRow === "themes" || root.themeFilter.length > 0
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.themeFilter
          color: root.foreground
          opacity: 0.9
          style: Text.Outline
          styleColor: Util.alpha(root.dimColor, 0.7)
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
        }
      }

      Item {
        id: carousel
        anchors.top: folderChrome.bottom
        anchors.topMargin: Style.space(10)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomChromeHeight
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
        clip: false
        opacity: root.focusRow === "themes" ? 1 : 0.78
        readonly property real itemStep: root.sliceWidth + root.sliceSpacing
        readonly property real previewX: (width - root.expandedWidth) / 2

        Repeater {
          model: root.imageArray.length
          delegate: Item {
            id: item
            required property int index
            readonly property var imageData: root.imageArray[index]
            readonly property bool matched: root.itemMatches(index)
            readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
            readonly property bool selected: matched && index === root.selectedIndex
            readonly property bool nearby: matched && Math.abs(relativeIndex) <= 16
            property bool sourceActivated: nearby
            onNearbyChanged: if (nearby) sourceActivated = true

            visible: nearby
            x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
            width: selected ? root.expandedWidth : root.sliceWidth
            height: selected ? root.expandedHeight : root.sliceHeight
            y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
            z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

            readonly property real skAbs: Math.abs(root.skewOffset)
            readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
            readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
            readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
            readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

            Item {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: true
              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "white"
                  strokeColor: "transparent"
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }
              Image {
                anchors.fill: parent
                source: item.sourceActivated && imageData && imageData.thumbnailPath ? Util.fileUrl(imageData.thumbnailPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: !item.selected
                cache: true
                smooth: true
                sourceSize.width: item.selected ? 960 : 240
                sourceSize.height: item.selected ? 540 : 160
              }
              Rectangle {
                anchors.fill: parent
                color: Util.alpha(root.dimColor, item.selected ? 0 : 0.42)
              }
            }

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "transparent"
                strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
                strokeWidth: item.selected ? 3 : 1
                startX: item.topLeft; startY: 0
                PathLine { x: item.topRight; y: 0 }
                PathLine { x: item.bottomRight; y: item.height }
                PathLine { x: item.bottomLeft; y: item.height }
                PathLine { x: item.topLeft; y: 0 }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: item.selected ? root.applySelected() : root.select(index)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        id: selectedLabel
        anchors.top: carousel.bottom
        anchors.topMargin: Style.space(12)
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: root.currentLabel()
        color: root.foreground
        style: Text.Outline
        styleColor: Util.alpha(root.dimColor, 0.7)
        font.pixelSize: Style.font.display
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

    }
      Rectangle {
        id: hintBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(18)
        width: hintText.implicitWidth + Style.space(32)
        height: Style.space(34)
        radius: Style.cornerRadius
        color: Util.alpha(root.dimColor, 0.62)
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.14)
        Text {
          textFormat: Text.PlainText
          id: hintText
          anchors.centerIn: parent
          text: "↑ folders   ↓ themes   ←/→ move   type to filter   Enter apply   Esc close"
          color: root.foreground
          opacity: 0.92
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        visible: !!(root.service && root.service.pendingManualSlug)
        anchors.fill: parent
        z: 80
        color: Util.alpha(root.dimColor, 0.72)
        MouseArea { anchors.fill: parent; onClicked: if (root.service) root.service.cancelManualApply() }
        Rectangle {
          width: 440
          height: 180
          radius: Style.cornerRadius
          color: root.dimColor
          border.color: root.selectedBorder
          border.width: 1
          anchors.centerIn: parent
          MouseArea { anchors.fill: parent; onClicked: { } }
          Column {
            anchors.centerIn: parent
            spacing: Style.space(12)
            width: 400
            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: {
                var name = (Model.themeBySlug(root.service ? root.service.themes : [], root.service ? root.service.pendingManualSlug : "") || { name: "this theme" }).name
                return "Apply “" + name + "”? " + Model.scheduleActiveLabel(root.service ? root.service.config : {}) + " is on and will be turned off."
              }
              color: root.foreground
              font.family: Style.font.family
            }
            Row {
              spacing: Style.space(8)
              Rectangle {
                width: 80
                height: Style.space(30)
                radius: Style.cornerRadius
                color: Util.alpha(root.foreground, 0.08)
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "Cancel"; color: root.foreground; font.family: Style.font.family }
                MouseArea { anchors.fill: parent; onClicked: if (root.service) root.service.cancelManualApply() }
              }
              Rectangle {
                width: applyStopLab.implicitWidth + Style.space(20)
                height: Style.space(32)
                radius: Style.cornerRadius
                color: Util.alpha(root.selectedBorder, 0.28)
                Text {
                  textFormat: Text.PlainText
                  id: applyStopLab
                  anchors.centerIn: parent
                  text: "Apply and stop schedule"
                  color: root.foreground
                  font.family: Style.font.family
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    if (root.service) root.service.confirmManualApply()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
