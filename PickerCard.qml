pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

Item {
  id: card
  property string source: ""
  property bool selected: false
  property bool activeTheme: false
  property bool rowFocused: false
  property real skew: 14
  property int previewWidth: 960
  signal clicked()

  Rectangle {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Style.space(8)
    anchors.rightMargin: card.skew + Style.space(8)
    width: activeLabel.implicitWidth + Style.space(12)
    height: activeLabel.implicitHeight + Style.space(6)
    radius: Style.cornerRadius
    z: 2
    visible: card.activeTheme && card.selected
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

  Item {
    id: mask
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
        startX: card.skew; startY: 0
        PathLine { x: card.width; y: 0 }
        PathLine { x: card.width - card.skew; y: card.height }
        PathLine { x: 0; y: card.height }
        PathLine { x: card.skew; y: 0 }
      }
    }
  }

  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: mask
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }
    Rectangle { anchors.fill: parent; color: Color.background }
    Image {
      anchors.fill: parent
      source: card.source ? Util.fileUrl(card.source) : ""
      sourceSize.width: card.previewWidth
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
    }
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, card.selected ? (card.rowFocused ? 0 : 0.18) : 0.48)
    }
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "transparent"
      strokeColor: card.selected && card.rowFocused ? Color.imagePicker.selectedBorder : Color.imagePicker.unselectedBorder
      strokeWidth: card.selected && card.rowFocused ? 2 : 1
      startX: card.skew; startY: 0
      PathLine { x: card.width; y: 0 }
      PathLine { x: card.width - card.skew; y: card.height }
      PathLine { x: 0; y: card.height }
      PathLine { x: card.skew; y: 0 }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: card.clicked()
  }
}
