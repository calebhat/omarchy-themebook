import QtQuick
import QtMultimedia

// Plays one muted live background in the theme preview. The strip stays a still.
Item {
  id: root

  property string fileUrl: ""

  Video {
    id: player
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectCrop
    loops: MediaPlayer.Infinite
    muted: true
    autoPlay: true
    source: root.fileUrl

    onSourceChanged: if (root.fileUrl) play()
  }
}
