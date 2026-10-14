import QtQuick
import qs.Commons
import qs.Ui
import "AktKit.js" as Model

Column {
  id: root

  required property var source
  required property var pad
  property bool connected: false
  property bool framePane: false   // the window shows its own frame picker below this card
  property bool wide: false        // two columns: key, direction and layout on the left, apps on the right
  readonly property real colGap: Style.space(20)
  readonly property real colW: wide ? Math.floor((width - colGap) / 2) : width
  readonly property bool isLayer: pad.layer === true
  readonly property string userKey: isLayer ? (source.snap.detected.fullscreen || "") : (source.snap.detected.pads[pad.id] || "")
  readonly property var fsInfo: source.snap.fullscreen
  readonly property string magnet: fsInfo.magnet
  readonly property bool isMagnet: isLayer ? magnet === "" : magnet === pad.id
  readonly property bool magnetFree: magnet === "off"
  readonly property int running: source.snap.running ? (source.snap.running[pad.id] || 0) : 0
  readonly property var layoutOptions: Model.layoutOptions([pad.layout])
  readonly property var motion: Model.motionOf(pad)
  readonly property bool inSides: Model.effectInfo(motion.inEffect).sides
  readonly property bool outSides: Model.effectInfo(motion.outEffect).sides
  readonly property var effectOptions: Model.EFFECTS.map(e => ({ value: e.id, label: e.label }))
  readonly property var sideOptions: Model.DIRECTIONS.map(d => ({ value: d, label: d === "right" ? "Right" : "Bottom" }))
  readonly property bool ownsIdentity: !isLayer || connected
  readonly property bool frameOn: source.hasStyles
  readonly property bool fullscreenOn: fsInfo.on && (isLayer || connected)
  readonly property var styleOptions: source.snap.styles.map(s => ({ value: s, label: s }))

  spacing: Style.space(8)

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.source.dim
    font.family: root.source.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Row {
    spacing: Style.space(8)
    width: parent.width

    GuardedField {
      id: nameField
      visible: root.ownsIdentity
      width: parent.width - showButton.width - (removeButton.visible ? removeButton.width : 0) - parent.spacing * (removeButton.visible ? 2 : 1)
      maximumLength: 40
      Binding { target: nameField; property: "text"; value: root.pad.label }   // a Binding, so typing does not break it
      foreground: root.source.foreground
      fontFamily: root.source.fontFamily
      onEditingFinished: if (text !== root.pad.label && text.trim() !== "") root.source.run(["padSet", root.pad.id, "label", text.trim()])
    }
    Button {
      id: showButton
      text: "Show"
      bordered: true
      focusable: true
      fontFamily: root.source.fontFamily
      foreground: root.source.foreground
      tooltipText: root.isLayer ? "Show or hide this layer (opens only when something is on it)" : "Slide this scratchpad in or out"
      onClicked: root.source.run(["toggle", root.pad.id])
    }
    Button {
      id: removeButton
      visible: !root.pad.builtin && !root.isLayer
      text: "Remove"
      bordered: true
      focusable: true
      fontFamily: root.source.fontFamily
      foreground: root.source.foreground
      onClicked: root.source.run(["padRemove", root.pad.id])
    }
  }

  Grid {
    width: parent.width
    columns: root.wide ? 2 : 1
    columnSpacing: root.colGap
    rowSpacing: root.spacing

    Column {
      width: root.colW
      spacing: root.spacing
      Caption { text: "KEY" }
      AktKeyButton {
        source: root.source
        slot: root.isLayer ? "fullscreen|key" : root.pad.id + "|key"
        value: root.pad.key || ""
        emptyText: root.isLayer ? (root.userKey !== "" ? root.userKey + " (your own binding)" : "not set")
                                : (root.pad.builtin ? "SUPER + S (Omarchy default)" : "not set")
      }

      Column {
        visible: root.userKey !== ""
        width: parent.width
        spacing: Style.space(4)
        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Your bindings.lua already binds " + root.userKey + " for this " + (root.isLayer ? "layer" : "scratchpad") + ". Leaving it alone."
          color: root.source.dim
          font.family: root.source.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Row {
          visible: !root.isLayer
          spacing: Style.space(8)
          ToggleSwitch {
            checked: root.pad.keepMine === true
            foreground: root.source.foreground
            onToggled: root.source.run(["padSet", root.pad.id, "keepMine", checked ? "false" : "true"])
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.colW - Style.space(60)
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Keep my binding (the slide direction needs this plugin's own key)"
            color: root.source.foreground
            font.family: root.source.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Column {
        visible: !root.pad.builtin && !root.isLayer
        width: parent.width
        spacing: Style.space(8)
        Caption { text: "MOVE WINDOW HERE" }
        AktKeyButton {
          source: root.source
          slot: root.pad.id + "|moveKey"
          value: root.pad.moveKey || ""
        }
      }

      Row {
        spacing: Style.space(12)
        Dropdown {
          width: Style.space(170)
          label: "Comes in"
          fontFamily: root.source.fontFamily
          options: root.effectOptions
          value: root.motion.inEffect
          onChanged: function(v) { root.source.run(["padSet", root.pad.id, "effect", v]) }
        }
        Dropdown {
          visible: root.inSides
          width: Style.space(130)
          label: "From"
          fontFamily: root.source.fontFamily
          options: root.sideOptions
          value: root.motion.inSide
          onChanged: function(v) { root.source.run(["padSet", root.pad.id, "direction", v]) }
        }
      }
      Row {
        spacing: Style.space(12)
        Dropdown {
          width: Style.space(170)
          label: "Goes out"
          fontFamily: root.source.fontFamily
          options: [{ value: "", label: "Same as coming in" }].concat(root.effectOptions)
          value: Model.cleanEffect(root.pad.outEffect)
          onChanged: function(v) { root.source.run(["padSet", root.pad.id, "outEffect", v === "" ? "same" : v]) }
        }
        Dropdown {
          visible: root.outSides
          width: Style.space(130)
          label: "To"
          fontFamily: root.source.fontFamily
          options: [{ value: "", label: "Same side" }].concat(root.sideOptions)
          value: Model.cleanSide(root.pad.outDirection)
          onChanged: function(v) { root.source.run(["padSet", root.pad.id, "outDirection", v === "" ? "same" : v]) }
        }
      }
      Dropdown {
        visible: root.ownsIdentity
        width: Style.space(190)
        label: "Layout"
        fontFamily: root.source.fontFamily
        options: root.layoutOptions
        value: root.pad.layout
        onChanged: function(v) { root.source.run(["padSet", root.pad.id, "layout", v === "" ? "default" : v]) }
      }

      Column {
        visible: root.frameOn && !root.isLayer && !root.framePane
        width: parent.width
        spacing: Style.space(8)
        Caption { text: "FRAME" }
        Row {
          spacing: Style.space(10)
          Dropdown {
            width: Style.space(260)
            showLabel: false
            label: "Frame"
            fontFamily: root.source.fontFamily
            options: root.styleOptions
            value: root.pad.style ? root.pad.style : source.snap.sharedStyle
            onChanged: function(v) { root.source.run(["padSet", root.pad.id, "style", v]) }
          }
        }
      }

      Row {
        visible: root.frameOn && !root.isLayer
        spacing: Style.space(8)
        ToggleSwitch {
          checked: root.pad.fit === true
          foreground: root.source.foreground
          onToggled: root.source.run(["padSet", root.pad.id, "fit", checked ? "off" : "on"])
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.colW - Style.space(60)
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Fit the frame to the windows (a small window gets a small frame)"
          color: root.source.foreground
          font.family: root.source.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }


    }
    Column {
      width: root.colW
      spacing: root.spacing
      Row {
        visible: root.fullscreenOn
        spacing: Style.space(8)
        enabled: root.isMagnet || root.magnetFree
        opacity: enabled ? 1 : 0.4
        ToggleSwitch {
          checked: root.isMagnet
          foreground: root.source.foreground
          onToggled: root.source.run(["magnet", root.isMagnet ? "off" : (root.isLayer ? "none" : root.pad.id)])
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.colW - Style.space(60)
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Fullscreen games land here"
          color: root.source.foreground
          font.family: root.source.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Row {
        visible: root.fullscreenOn && root.isMagnet
        spacing: Style.space(8)
        ToggleSwitch {
          checked: root.fsInfo.muteOnHide === true
          foreground: root.source.foreground
          onToggled: root.source.run(["muteOnHide", checked ? "off" : "on"])
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.colW - Style.space(60)
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Mute the game while the layer is hidden"
          color: root.source.foreground
          font.family: root.source.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Row {
        visible: root.ownsIdentity
        spacing: Style.space(8)
        width: parent.width
        Caption {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - restartButton.width - parent.spacing
          text: "APPS STARTED AT LOGIN" + (root.running > 0 ? "  (" + root.running + " open)" : "")
        }
        Button {
          id: restartButton
          visible: root.pad.apps.length > 0
          text: root.running > 0 ? "Restart apps" : "Start apps"
          bordered: true
          focusable: true
          fontFamily: root.source.fontFamily
          foreground: root.source.foreground
          tooltipText: root.running > 0 ? "Close the apps this plugin started here and start them again" : "Start these apps now"
          onClicked: root.source.run(["appsRestart", root.pad.id])
        }
      }
      Repeater {
        model: root.ownsIdentity ? root.pad.apps : []
        delegate: Row {
          required property string modelData
          required property int index
          spacing: Style.space(8)
          width: root.colW
          Text {
            width: parent.width - dropApp.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.source.appTitle(modelData)
            elide: Text.ElideRight
            color: root.source.foreground
            font.family: root.source.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Button {
            id: dropApp
            text: "Remove"
            focusable: true
            fontFamily: root.source.fontFamily
            foreground: root.source.foreground
            onClicked: root.source.run(["appRemove", root.pad.id, String(index)])
          }
        }
      }
      SearchableDropdown {
        visible: root.ownsIdentity
        id: appPicker
        width: parent.width
        showLabel: false
        foreground: root.source.foreground
        fontFamily: root.source.fontFamily
        options: root.source.appChoices
        placeholderText: "Search installed apps to add..."
        triggerLabel: "Search installed apps to add..."
        emptyText: "No installed app matches"
        value: ""
        onChanged: function(v) { root.source.run(["appAdd", root.pad.id, v]); value = "" }
      }
      GuardedField {
        visible: root.ownsIdentity
        width: parent.width
        maximumLength: 300
        placeholderText: "or type a command, then Enter"
        foreground: root.source.foreground
        fontFamily: root.source.fontFamily
        onAccepted: if (text.trim() !== "") { root.source.run(["appAdd", root.pad.id, text.trim()]); text = "" }
      }
    }
  }
}
