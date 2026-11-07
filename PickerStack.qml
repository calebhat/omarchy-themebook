pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: stack
  property var groups: []
  property var favorites: []
  property string folderId: ""
  property string selectedSlug: ""
  property string activeSlug: ""
  property var remembered: ({})
  property string query: ""
  property bool shown: false
  property int firstVisibleRow: 0
  property real windowStart: 0
  property int sizeFocusIndex: 0
  property int pendingFirst: 0
  property bool animateWindow: false
  property bool animateSizes: false
  readonly property int groupCount: (stack.groups && stack.groups.length) ? stack.groups.length : 0
  readonly property int foldersAbove: Math.max(0, stack.groupIndex)
  readonly property int foldersBelow: Math.max(0, stack.groupCount - 1 - stack.groupIndex)
  readonly property color labelColor: Color.imagePicker.text
  signal chosen(string groupId, var image)
  signal activated()

  readonly property int groupIndex: {
    var list = stack.groups || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].id === stack.folderId) return i
    return 0
  }

  onGroupIndexChanged: stack.syncWindow()
  onGroupCountChanged: stack.snapWindow()
  onShownChanged: {
    if (shown) stack.snapWindow()
    else {
      stack.animateWindow = false
      stack.animateSizes = false
      shrinkTimer.stop()
      slideAnim.stop()
    }
  }

  NumberAnimation {
    id: slideAnim
    target: stack
    property: "windowStart"
    duration: 146
    easing.type: Easing.InOutCubic
    onFinished: stack.finishExpand()
  }

  Timer {
    id: shrinkTimer
    interval: 67
    repeat: false
    onTriggered: stack.startSlide()
  }

  function groupAt(i) {
    var list = stack.groups || []
    if (i < 0 || i >= list.length || !list[i]) return { id: "", name: "", images: [] }
    return list[i]
  }

  function targetWindowStart() {
    // Keep the focused folder in the middle slot. -1 shows empty space
    // above the first folder; n-2 shows empty space below the last.
    return stack.groupIndex - 1
  }

  function stopFolderMotion() {
    shrinkTimer.stop()
    slideAnim.stop()
  }

  function snapWindow() {
    stack.stopFolderMotion()
    stack.animateWindow = false
    stack.animateSizes = false
    var first = stack.targetWindowStart()
    stack.firstVisibleRow = first
    stack.pendingFirst = first
    stack.windowStart = first
    stack.sizeFocusIndex = stack.groupIndex
    if (stack.shown) {
      Qt.callLater(function() {
        stack.animateWindow = true
        stack.animateSizes = true
      })
    }
  }

  function startSlide() {
    stack.firstVisibleRow = stack.pendingFirst
    if (Math.abs(stack.windowStart - stack.pendingFirst) < 0.01) {
      stack.finishExpand()
      return
    }
    slideAnim.stop()
    slideAnim.from = stack.windowStart
    slideAnim.to = stack.pendingFirst
    slideAnim.start()
  }

  function finishExpand() {
    stack.windowStart = stack.pendingFirst
    stack.firstVisibleRow = stack.pendingFirst
    stack.sizeFocusIndex = stack.groupIndex
  }

  function syncWindow() {
    var first = stack.targetWindowStart()
    var needsSlide = Math.abs(first - stack.windowStart) > 0.02
    if (!needsSlide) {
      stack.stopFolderMotion()
      stack.firstVisibleRow = first
      stack.pendingFirst = first
      stack.sizeFocusIndex = stack.groupIndex
      return
    }
    stack.pendingFirst = first
    var alreadyCompact = stack.sizeFocusIndex === -1
    stack.sizeFocusIndex = -1
    if (alreadyCompact && !shrinkTimer.running) {
      stack.startSlide()
      return
    }
    if (shrinkTimer.running) return
    shrinkTimer.restart()
  }

  function favoriteMark(image) {
    if (!image || !image.slug) return ""
    var fav = stack.favorites || []
    for (var i = 0; i < fav.length; i++)
      if (fav[i] === image.slug) return "  ♥"
    return ""
  }

  MouseArea {
    z: -1
    anchors.fill: parent
    enabled: stack.shown
    onClicked: {}
    onWheel: function(event) {
      if (wheelPause.running) { event.accepted = true; return }
      if (Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y))
        stack.moveTheme(event.angleDelta.x > 0 ? -1 : 1)
      else
        stack.moveGroup(event.angleDelta.y > 0 ? -1 : 1)
      wheelPause.start()
      event.accepted = true
    }
  }
  Timer { id: wheelPause; interval: 73 }

  function moveGroup(direction) {
    var n = stack.groupCount
    if (!n) return
    var i = Math.max(0, Math.min(n - 1, stack.groupIndex + direction))
    var g = stack.groupAt(i)
    var img = g.images[Model.groupThemeIndex(g.images, stack.remembered[g.id], stack.activeSlug)] || g.images[0] || null
    stack.chosen(g.id, img || { slug: "" })
  }

  function moveTheme(direction) {
    var g = stack.groupAt(stack.groupIndex)
    if (!g.images || !g.images.length) return
    var idx = Model.groupThemeIndex(g.images, stack.remembered[g.id] || stack.selectedSlug, stack.activeSlug)
    var next = (idx + direction + g.images.length) % g.images.length
    stack.chosen(g.id, g.images[next])
  }

  Item {
    id: stage
    readonly property int rowPitch: 330
    width: 1040
    height: 3 * rowPitch + 110
    anchors.centerIn: parent
    readonly property real fitScale: {
      var w = stack.width
      var h = stack.height
      if (!(w > 200) || !(h > 200)) return 1
      var s = Math.min(1.25, (w - 64) / stage.width, (h - 140) / stage.height)
      if (!(s > 0.25)) return 0.5
      return s
    }
    scale: fitScale
    clip: true
    visible: stack.shown
    enabled: stack.shown
    opacity: stack.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.InOutQuad } }

    Item {
      id: strip
      width: parent.width
      height: Math.max(stage.rowPitch, stack.groupCount * stage.rowPitch)
      y: 40 - stack.windowStart * stage.rowPitch

    Repeater {
      model: stack.groupCount
      delegate: Item {
        id: row
        required property int index
        readonly property var group: stack.groupAt(index)
        readonly property var images: group.images || []
        readonly property bool selected: index === stack.groupIndex
        readonly property bool sizeFocused: index === stack.sizeFocusIndex
        readonly property int selectedIndex: Model.groupThemeIndex(images, stack.remembered[group.id] || stack.selectedSlug, stack.activeSlug)
        readonly property var selectedImage: images[selectedIndex] || null
        readonly property bool inWindow: {
          var a = stack.windowStart
          var b = stack.pendingFirst
          var lo = Math.floor(Math.min(a, b)) - 1
          var hi = Math.ceil(Math.max(a, b)) + 3
          return index >= lo && index < hi
        }
        readonly property bool inSlots: {
          var s = stack.windowStart
          return index >= Math.floor(s) && index <= Math.floor(s) + 2
        }
        readonly property var neighborItems: inWindow ? Model.neighbors(images, selectedIndex, 5) : []
        property real previewWidth: sizeFocused ? 414 : 220
        property real previewHeight: sizeFocused ? 240 : 115
        property real step: sizeFocused ? 49 : 27
        property real sliceWidth: sizeFocused ? 71 : 40
        readonly property real stackWidth: previewWidth + 10 * step
        Behavior on previewWidth {
          enabled: stack.animateSizes
          NumberAnimation { duration: 79; easing.type: Easing.InOutCubic }
        }
        Behavior on previewHeight {
          enabled: stack.animateSizes
          NumberAnimation { duration: 79; easing.type: Easing.InOutCubic }
        }
        Behavior on step {
          enabled: stack.animateSizes
          NumberAnimation { duration: 79; easing.type: Easing.InOutCubic }
        }
        Behavior on sliceWidth {
          enabled: stack.animateSizes
          NumberAnimation { duration: 79; easing.type: Easing.InOutCubic }
        }
        width: stage.width
        height: stage.rowPitch
        y: index * stage.rowPitch
        clip: true
        visible: inWindow
        opacity: selected ? 1 : 0.7
        z: sizeFocused || selected ? 2 : 1
        Behavior on opacity { NumberAnimation { duration: 67 } }

        Text {
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          width: row.previewWidth
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          y: 0
          text: row.group.name + "  " + row.images.length
          color: row.selected ? Color.accent : stack.labelColor
          style: Text.Outline
          styleColor: Util.alpha(Color.background, 0.7)
          font.family: Style.font.family
          font.pixelSize: row.selected ? Style.font.title : Style.font.body
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: stack.chosen(row.group.id, row.selectedImage || row.images[0] || { slug: "" })
          }
        }

        Repeater {
          model: row.neighborItems.length
          delegate: PickerCard {
            required property int index
            readonly property var item: row.neighborItems[index] || ({ image: null, offset: 0 })
            readonly property int offset: item.offset
            selected: offset === 0
            activeTheme: item.image && item.image.slug === stack.activeSlug
            rowFocused: row.sizeFocused
            source: item.image && item.image.thumbnailPath ? item.image.thumbnailPath : ""
            width: selected ? row.previewWidth : row.sliceWidth
            height: selected ? row.previewHeight : row.previewHeight * 0.92
            skew: row.sizeFocused ? 14 : 8
            x: selected ? (row.width - row.previewWidth) / 2
              : offset < 0 ? (row.width - row.previewWidth) / 2 + offset * row.step
              : (row.width + row.previewWidth) / 2 - (row.sliceWidth - row.step) + (offset - 1) * row.step
            y: 30
            z: selected ? 100 : 50 - Math.abs(offset)
            onClicked: {
              if (row.selected && offset === 0) stack.activated()
              else if (item.image) stack.chosen(row.group.id, item.image)
            }
          }
        }

        Rectangle {
          visible: row.images.length === 0
          width: row.previewWidth + 120
          height: row.previewHeight
          anchors.horizontalCenter: parent.horizontalCenter
          y: 30
          color: Util.alpha(Color.background, 0.3)
          border.color: Color.imagePicker.unselectedBorder
          radius: Style.cornerRadius
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            width: parent.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: stack.query ? "No matching themes" : row.group.id === "favorites"
              ? "Press Ctrl+F to add a theme\nto Favorites."
              : "No themes in this folder"
            color: stack.labelColor
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            anchors.fill: parent
            onClicked: stack.chosen(row.group.id, { slug: "" })
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: row.inSlots && !!row.selectedImage
          anchors.horizontalCenter: parent.horizontalCenter
          y: 38 + row.previewHeight
          width: row.stackWidth
          height: 24
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: row.selectedImage ? (row.selectedImage.name || row.selectedImage.slug) + stack.favoriteMark(row.selectedImage) : ""
          color: row.selected ? Color.accent : stack.labelColor
          style: Text.Outline
          styleColor: Util.alpha(Color.background, 0.7)
          font.family: Style.font.family
          font.pixelSize: row.selected ? Style.font.body : Style.font.caption
        }
      }
    }
    }
  }

  Rectangle {
    z: 20
    visible: stack.shown && stack.groupCount > 3
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(10)
    width: aboveLab.implicitWidth + Style.space(20)
    height: Style.space(28)
    radius: Style.cornerRadius
    color: Util.alpha(Color.background, 0.72)
    border.width: 1
    border.color: Util.alpha(stack.labelColor, 0.22)
    Text {
      textFormat: Text.PlainText
      id: aboveLab
      anchors.centerIn: parent
      text: stack.foldersAbove <= 0 ? "Top" : ("↑  " + stack.foldersAbove + " above")
      color: stack.labelColor
      opacity: stack.foldersAbove <= 0 ? 0.55 : 1
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: stack.foldersAbove > 0
    }
  }

  Rectangle {
    z: 20
    visible: stack.shown && stack.groupCount > 3
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(8)
    width: belowLab.implicitWidth + Style.space(20)
    height: Style.space(28)
    radius: Style.cornerRadius
    color: Util.alpha(Color.background, 0.72)
    border.width: 1
    border.color: Util.alpha(stack.labelColor, 0.22)
    Text {
      textFormat: Text.PlainText
      id: belowLab
      anchors.centerIn: parent
      text: stack.foldersBelow <= 0 ? "Last folder" : ("↓  " + stack.foldersBelow + " below")
      color: stack.labelColor
      opacity: stack.foldersBelow <= 0 ? 0.55 : 1
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: stack.foldersBelow > 0
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: stack.shown && stack.groupCount === 0
    anchors.centerIn: parent
    text: stack.query ? "No matching themes or folders" : "No folders in the picker"
    color: stack.labelColor
    style: Text.Outline
    styleColor: Util.alpha(Color.background, 0.7)
    font.family: Style.font.family
    font.pixelSize: Style.font.title
  }
}
