pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Model.js" as Model

Item {
  id: grid
  property var groups: []
  property var favorites: []
  property string folderId: ""
  property string selectedSlug: ""
  property string activeSlug: ""
  property bool shown: false
  property bool initialized: false
  property bool animateScroll: false
  property real layoutWidth: 1440
  property real layoutHeight: 800
  property int createdCards: 0
  property int liveCards: 0
  readonly property int columns: Math.max(2, Math.min(6, Math.floor(layoutWidth / 210)))
  readonly property real cellWidth: (layoutWidth - 12) / columns
  readonly property real cardWidth: cellWidth - 20
  readonly property real cardHeight: cardWidth * 0.60
  readonly property real cellHeight: cardHeight + 48
  readonly property var sections: Model.gridSections(groups, columns, cellHeight)
  readonly property int groupCount: (grid.groups && grid.groups.length) ? grid.groups.length : 0
  readonly property color labelColor: Color.imagePicker.text
  signal chosen(string groupId, var image)
  signal activated()

  function groupAt(i) {
    var list = grid.groups || []
    if (i < 0 || i >= list.length || !list[i]) return { id: "", name: "", images: [] }
    return list[i]
  }

  function favoriteMark(image) {
    if (!image || !image.slug) return ""
    var fav = grid.favorites || []
    for (var i = 0; i < fav.length; i++)
      if (fav[i] === image.slug) return "  ♥"
    return ""
  }

  function revealSelection() {
    if (!shown) return
    var section = null
    var list = grid.sections || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === grid.folderId) { section = list[i]; break }
    }
    if (!section) { viewport.contentY = 0; return }
    var index = 0
    for (var j = 0; j < section.images.length; j++) {
      if (section.images[j] && section.images[j].slug === grid.selectedSlug) { index = j; break }
    }
    var top = section.top + (index < columns ? 0 : 40 + Math.floor(index / columns) * cellHeight)
    var bottom = section.top + 40 + (Math.floor(Math.max(0, index) / columns) + 1) * cellHeight
    var next = viewport.contentY
    if (top < next) next = top
    else if (bottom > next + viewport.height) next = bottom - viewport.height
    viewport.contentY = Math.max(0, Math.min(next, Math.max(0, viewport.contentHeight - viewport.height)))
  }

  onSelectedSlugChanged: Qt.callLater(revealSelection)
  onFolderIdChanged: Qt.callLater(revealSelection)
  onSectionsChanged: Qt.callLater(revealSelection)

  function settleOpening() {
    if (!shown) return
    updateGeometry()
    revealSelection()
    initialized = true
    Qt.callLater(function() { grid.animateScroll = grid.shown })
  }

  function updateGeometry() {
    if (!shown || width <= 0 || height <= 0) return
    layoutWidth = width
    layoutHeight = height
  }

  onWidthChanged: if (shown) Qt.callLater(updateGeometry)
  onHeightChanged: if (shown) Qt.callLater(updateGeometry)
  onShownChanged: {
    animateScroll = false
    if (shown) Qt.callLater(settleOpening)
  }

  Flickable {
    id: viewport
    anchors.centerIn: parent
    width: grid.layoutWidth
    height: grid.layoutHeight
    contentWidth: width
    contentHeight: grid.sections.length ? grid.sections[grid.sections.length - 1].top + grid.sections[grid.sections.length - 1].height : 0
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Behavior on contentY {
      enabled: grid.animateScroll && !viewport.dragging && !viewport.flicking
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Repeater {
      model: grid.groupCount
      delegate: Item {
        id: section
        required property int index
        readonly property var group: grid.groupAt(index)
        readonly property var images: group.images || []
        readonly property var geometry: grid.sections[index] || ({ top: 0, height: 0 })
        x: 0
        y: geometry.top
        width: viewport.width - 12
        height: geometry.height

        Text {
          textFormat: Text.PlainText
          width: parent.width
          height: 24
          horizontalAlignment: Text.AlignHCenter
          text: section.group.name + "  " + section.images.length
          color: section.group.id === grid.folderId ? Color.accent : grid.labelColor
          style: Text.Outline
          styleColor: Util.alpha(Color.background, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: !section.images.length
          anchors.horizontalCenter: parent.horizontalCenter
          y: 64
          text: section.group.id === "favorites" ? "Press Ctrl+F to add a theme to Favorites." : "No themes in this folder"
          color: grid.labelColor
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        readonly property int firstTile: Math.min(section.images.length,
          Math.max(0, Math.floor((viewport.contentY - section.y - 40) / grid.cellHeight) - 1) * grid.columns)
        readonly property int lastTile: Math.min(section.images.length,
          Math.max(0, Math.ceil((viewport.contentY + viewport.height - section.y - 40) / grid.cellHeight) + 1) * grid.columns)
        readonly property int tileCount: Math.max(0, lastTile - firstTile)

        Repeater {
          model: grid.initialized ? section.tileCount : 0
          delegate: Item {
            id: tile
            required property int index
            readonly property int absoluteIndex: section.firstTile + index
            readonly property var image: section.images[absoluteIndex] || ({ slug: "", name: "", thumbnailPath: "" })
            readonly property bool selected: section.group.id === grid.folderId && image.slug === grid.selectedSlug
            readonly property real absoluteY: section.y + y
            readonly property bool nearViewport: absoluteY + height >= viewport.contentY - grid.cellHeight && absoluteY <= viewport.contentY + viewport.height + grid.cellHeight
            x: (absoluteIndex % grid.columns) * grid.cellWidth + 10
            y: 40 + Math.floor(absoluteIndex / grid.columns) * grid.cellHeight
            width: grid.cardWidth
            height: grid.cellHeight

            Loader {
              active: grid.initialized && tile.nearViewport
              width: parent.width
              height: grid.cardHeight
              sourceComponent: PickerGridCard {
                Component.onCompleted: { grid.createdCards++; grid.liveCards++ }
                Component.onDestruction: grid.liveCards--
                activeTheme: tile.image.slug === grid.activeSlug
                source: tile.image.thumbnailPath || ""
                previewWidth: 480
                rowFocused: tile.selected
                onClicked: {
                  if (tile.selected) grid.activated()
                  else grid.chosen(section.group.id, tile.image)
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              y: grid.cardHeight + 10
              width: parent.width
              height: 24
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: (tile.image.name || tile.image.slug) + grid.favoriteMark(tile.image)
              color: tile.selected ? Color.accent : grid.labelColor
              style: Text.Outline
              styleColor: Util.alpha(Color.background, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  Rectangle {
    anchors.right: parent.right
    width: 2
    height: Math.max(30, viewport.height * Math.min(1, viewport.height / Math.max(1, viewport.contentHeight)))
    y: viewport.visibleArea.yPosition * viewport.height
    visible: viewport.contentHeight > viewport.height
    color: Color.accent
    opacity: 0.4
  }
}
