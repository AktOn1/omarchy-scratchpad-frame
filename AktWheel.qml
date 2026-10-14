import QtQuick

// Mouse-wheel scrolling for a Flickable/ListView. Qt's own wheel handling is a small flick (~70 px a notch at 100%)
// that decelerates, so every panel built on it feels slow next to a browser or terminal. This moves contentY directly,
// ~150 px a notch (touchpads use their own pixelDelta). Usage: `AktWheel { view: myFlickable }` inside the Flickable.
WheelHandler {
  id: root

  required property Flickable view
  property real gain: 1.25

  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  orientation: Qt.Vertical

  onWheel: function(event) {
    var v = root.view
    if (!v) return
    var d = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y * root.gain
    var top = v.originY - v.topMargin
    var bottom = Math.max(top, v.originY + v.contentHeight + v.bottomMargin - v.height)
    v.cancelFlick()
    v.contentY = Math.max(top, Math.min(bottom, v.contentY - d))
  }
}
