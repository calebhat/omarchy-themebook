pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

Item {
  id: card
  property string source: ""
  property bool activeTheme: false
  property bool rowFocused: false
  property int previewWidth: 480
  signal clicked()

  Rectangle { anchors.fill: parent; color: Color.background }

  Image {
    anchors.fill: parent
    source: card.source ? Util.fileUrl(card.source) : ""
    sourceSize.width: card.previewWidth
    fillMode: Image.PreserveAspectCrop
    clip: true
    asynchronous: true
    cache: true
  }

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, card.rowFocused ? 0 : 0.18)
    border.color: card.rowFocused ? Color.imagePicker.selectedBorder : Color.imagePicker.unselectedBorder
    border.width: card.rowFocused ? 2 : 1
  }

  Rectangle {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(8)
    width: activeLabel.implicitWidth + Style.space(12)
    height: activeLabel.implicitHeight + Style.space(6)
    radius: Style.cornerRadius
    visible: card.activeTheme
    color: Color.background
    border.color: Color.accent
    Text {
      textFormat: Text.PlainText
      id: activeLabel
      anchors.centerIn: parent
      text: "Active"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: card.clicked()
  }
}
