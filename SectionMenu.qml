import QtQuick
import qs.Commons

// SHARED SOURCE (omarchy-plugins/shared/menu/SectionMenu.qml). Do not edit the copy inside a plugin; edit the shared file and run
// omarchy-plugins/tools/sync-shared.sh. One effect menu: categories on the left, items on the right, keyboard state inside.
// The owner reacts to pointed (hover or keyboard highlight), chosen and acted signals and passes fg / fontFamily from its bar.
Item {
  id: sec
  property string title: ""
  property color fg: "white"
  property string fontFamily: ""
  property string checkGlyph: "󰄬"
  property var cats: []
  property string saved: ""
  property var favs: []
  property bool focused: false
  property int defaultCat: 0
  property int col: 0
  property int catIdx: 0
  property int itemIdx: 0
  property point lastPt: Qt.point(-100, -100)
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function fgA(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
  readonly property int rowH: Style.space(28)
  readonly property int rowGap: Style.space(2)
  property int visibleRows: 13
  readonly property var curCat: cats.length > 0 ? cats[sec.clamp(catIdx, 0, cats.length - 1)] : null
  readonly property var curItems: (curCat && curCat.items) ? curCat.items : []
  readonly property var selected: (col === 1 && itemIdx >= 0 && itemIdx < curItems.length) ? curItems[itemIdx] : null
  signal pointed(var item)
  signal chosen(var item, bool keep)
  signal acted(string id)
  signal focusRequested()

  implicitHeight: Style.space(24) + visibleRows * (rowH + rowGap)

  function indexOfSaved(ci) {
    if (saved === "" || ci < 0 || ci >= cats.length) return -1
    var it = cats[ci].items || []
    for (var j = 0; j < it.length; j++) if (it[j].id === saved) return j
    return -1
  }
  function catOfSaved() {
    for (var i = 0; i < cats.length; i++) if (cats[i].id !== "fav" && indexOfSaved(i) >= 0) return i
    return -1
  }
  function sync() {
    var ci = catOfSaved()
    if (ci >= 0) { catIdx = ci; itemIdx = indexOfSaved(ci); col = 1 }
    else { catIdx = Math.min(defaultCat, Math.max(0, cats.length - 1)); itemIdx = 0; col = 0 }
  }
  function gotoCat(n) {
    if (n < 0 || n >= cats.length) return
    col = 0
    catIdx = n
    itemIdx = Math.max(0, indexOfSaved(n))
  }
  // returns 1 when "right" was pressed on an effect (nothing further right in this menu),
  // -1 when "left" was pressed on a category (nothing further left), else 0
  function move(dx, dy) {
    if (dy !== 0) {
      if (col === 0) {
        catIdx = sec.clamp(catIdx + dy, 0, cats.length - 1)
        itemIdx = Math.max(0, indexOfSaved(catIdx))
      } else if (curItems.length > 0) {
        itemIdx = sec.clamp(itemIdx + dy, 0, curItems.length - 1)
        pointed(selected)
      }
    } else if (dx > 0) {
      if (col === 0) {
        if (curCat && curCat.action) acted(curCat.id)
        else if (curItems.length > 0) { col = 1; itemIdx = sec.clamp(itemIdx, 0, curItems.length - 1); pointed(selected) }
      } else {
        return 1
      }
    } else if (dx < 0) {
      if (col === 1) col = 0
      else return -1
    }
    return 0
  }
  function jump(last) {
    if (col === 0) { catIdx = last ? cats.length - 1 : 0; itemIdx = Math.max(0, indexOfSaved(catIdx)) }
    else if (curItems.length > 0) { itemIdx = last ? curItems.length - 1 : 0; pointed(selected) }
  }
  function activate(keep) {
    if (col === 0) {
      if (curCat && curCat.action) acted(curCat.id)
      else if (curItems.length > 0) { col = 1; itemIdx = sec.clamp(itemIdx, 0, curItems.length - 1); pointed(selected) }
    } else if (selected) {
      chosen(selected, keep)
    }
  }
  // pointer events also arrive when a list scrolls under a resting mouse; only real movement counts
  function realMove(area, m) {
    var p = area.mapToItem(null, m.x, m.y)
    if (Math.abs(p.x - lastPt.x) < 2 && Math.abs(p.y - lastPt.y) < 2) return false
    lastPt = p
    return true
  }
  function showSelected() {
    if (curItems.length > 0) list.positionViewAtIndex(sec.clamp(itemIdx, 0, curItems.length - 1), ListView.Contain)
  }
  function showCat() {
    if (cats.length > 0) catCol.positionViewAtIndex(sec.clamp(catIdx, 0, cats.length - 1), ListView.Contain)
  }
  onCatIdxChanged: showCat()
  onItemIdxChanged: showSelected()
  onCurItemsChanged: Qt.callLater(showSelected)

  Text {
    id: titleText
    height: Style.space(24)
    verticalAlignment: Text.AlignVCenter
    leftPadding: Style.space(10)
    textFormat: Text.PlainText
    text: sec.title.toUpperCase()
    opacity: sec.focused ? 0.95 : 0.45
    color: sec.fg
    font.family: sec.fontFamily
    font.pixelSize: Style.font.body * 0.8
    font.bold: true
    font.letterSpacing: 1
  }

  Row {
    id: panes
    anchors.top: titleText.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(8)

    ListView {
      id: catCol
      // Qt's own wheel step is tiny (~70 px a notch): move ~150 px a notch like a browser.
      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          var d = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y * 1.25
          catCol.cancelFlick()
          catCol.contentY = Math.max(catCol.originY, Math.min(Math.max(catCol.originY, catCol.originY + catCol.contentHeight - catCol.height), catCol.contentY - d))
        }
      }
      width: Math.round(sec.width * 0.34)
      height: sec.visibleRows * (sec.rowH + sec.rowGap)
      spacing: sec.rowGap
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: sec.cats

        delegate: Rectangle {
          id: catRow
          required property var modelData
          required property int index
          readonly property bool selected: index === sec.catIdx
          readonly property bool hasSaved: modelData.id !== "fav" && sec.indexOfSaved(index) >= 0
          width: catCol.width
          height: sec.rowH
          radius: Style.space(6)
          color: selected ? sec.fgA(sec.col === 0 && sec.focused ? 0.2 : 0.09) : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: marker.left
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: catRow.modelData.label
            color: sec.fg
            font.family: sec.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            id: marker
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: catRow.hasSaved ? "●" : (catRow.modelData.action ? "" : "›")
            opacity: catRow.hasSaved ? 1 : 0.45
            color: sec.fg
            font.family: sec.fontFamily
            font.pixelSize: Style.font.body * 0.85
          }
          MouseArea {
            id: catMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(m) {
              if (!sec.realMove(catMouse, m)) return
              sec.focusRequested()
              if (sec.catIdx !== catRow.index) { sec.catIdx = catRow.index; sec.itemIdx = Math.max(0, sec.indexOfSaved(catRow.index)) }
              sec.col = 0
            }
            onClicked: {
              sec.focusRequested()
              sec.catIdx = catRow.index
              if (catRow.modelData.action) sec.acted(catRow.modelData.id)
              else { sec.itemIdx = Math.max(0, sec.indexOfSaved(catRow.index)); sec.col = 1 }
            }
          }
        }
    }

    ListView {
      id: list
      // Qt's own wheel step is tiny (~70 px a notch): move ~150 px a notch like a browser.
      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          var d = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y * 1.25
          list.cancelFlick()
          list.contentY = Math.max(list.originY, Math.min(Math.max(list.originY, list.originY + list.contentHeight - list.height), list.contentY - d))
        }
      }
      width: panes.width - catCol.width - panes.spacing
      height: sec.visibleRows * (sec.rowH + sec.rowGap)
      spacing: sec.rowGap
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: sec.curItems

      delegate: Rectangle {
        id: itemRow
        required property var modelData
        required property int index
        readonly property bool isSaved: modelData.id === sec.saved
        readonly property bool selected: index === sec.itemIdx
        width: list.width
        height: sec.rowH
        radius: Style.space(6)
        color: selected ? sec.fgA(sec.col === 1 && sec.focused ? 0.2 : 0.07) : "transparent"

        Text {
          id: itemLabel
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: (sec.favs.indexOf(itemRow.modelData.id) >= 0 ? "★ " : "") + itemRow.modelData.label
          color: sec.fg
          font.family: sec.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          anchors.left: itemLabel.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: itemRow.isSaved ? sec.checkGlyph : (itemRow.modelData.hint || "")
          opacity: itemRow.isSaved ? 1 : 0.5
          color: sec.fg
          font.family: sec.fontFamily
          font.pixelSize: itemRow.isSaved ? Style.font.body : Style.font.body * 0.8
        }
        MouseArea {
          id: itemMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(m) {
            if (!sec.realMove(itemMouse, m)) return
            sec.focusRequested()
            sec.col = 1
            sec.itemIdx = itemRow.index
            sec.pointed(itemRow.modelData)
          }
          onClicked: {
            sec.focusRequested()
            sec.col = 1
            sec.itemIdx = itemRow.index
            sec.chosen(itemRow.modelData, false)
          }
        }
      }
    }
  }

  Text {
    visible: sec.curItems.length === 0 && sec.curCat !== null && !sec.curCat.action
    x: catCol.width + panes.spacing + Style.space(10)
    y: titleText.height + Style.space(8)
    width: list.width - Style.space(20)
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: sec.curCat && sec.curCat.note ? sec.curCat.note : ""
    opacity: 0.55
    color: sec.fg
    font.family: sec.fontFamily
    font.pixelSize: Style.font.body * 0.9
  }
}
