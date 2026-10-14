import QtQuick
import QtQuick.Shapes

// The Scratchpad Frame mark: a picture frame (outer and inner rim) with four corner studs. Drawn, so it follows the bar colour at any size.
Item {
  id: icon
  property real iconSize: 16
  property color color: "white"
  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Item {
    width: 24
    height: 24
    scale: icon.iconSize / 24
    transformOrigin: Item.TopLeft

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: icon.color
        strokeWidth: 1.9
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M5.5 3 H18.5 A2.5 2.5 0 0 1 21 5.5 V18.5 A2.5 2.5 0 0 1 18.5 21 H5.5 A2.5 2.5 0 0 1 3 18.5 V5.5 A2.5 2.5 0 0 1 5.5 3 Z" }
      }
      ShapePath {
        strokeColor: icon.color
        strokeWidth: 1.3
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M8.5 8 H15.5 A0.8 0.8 0 0 1 16.3 8.8 V15.2 A0.8 0.8 0 0 1 15.5 16 H8.5 A0.8 0.8 0 0 1 7.7 15.2 V8.8 A0.8 0.8 0 0 1 8.5 8 Z" }
      }
      ShapePath {
        strokeColor: "transparent"
        strokeWidth: 0
        fillColor: icon.color
        PathSvg { path: "M3 6.2 L6.2 3 L3 3 Z M17.8 3 L21 6.2 L21 3 Z M21 17.8 L17.8 21 L21 21 Z M6.2 21 L3 17.8 L3 21 Z" }
      }
    }
  }
}
