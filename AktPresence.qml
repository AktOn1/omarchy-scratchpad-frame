import QtQuick
import Quickshell
import Quickshell.Io

// Tells the other AktOn1 plugin that this plugin's bar icon is there (a heartbeat file), and watches the host's.
// A plugin combined into another hides its own icon only while the host's icon is really alive; if the host is gone, it shows again.
Item {
  id: root

  required property string selfName
  property string hostName: ""        // "" = this plugin is not a member
  property bool hostAlive: false
  property bool checked: false         // the host's file has been read at least once

  readonly property string base: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

  Process {
    id: prepare
    command: ["mkdir", "-p", root.base + "/" + root.selfName]
    onExited: root.beat()
    Component.onCompleted: running = true
  }

  FileView {
    id: mine
    path: root.base + "/" + root.selfName + "/widget-alive"
    atomicWrites: true
    printErrors: false
  }
  function beat() { mine.setText(String(Date.now())) }
  Timer { interval: 4000; repeat: true; running: true; onTriggered: root.beat() }

  FileView {
    id: theirs
    path: root.hostName !== "" ? root.base + "/" + root.hostName + "/widget-alive" : ""
    printErrors: false
    onLoaded: { root.hostAlive = Date.now() - Number(text().trim()) < 12000; root.checked = true }
    onLoadFailed: { root.hostAlive = false; root.checked = true }
  }
  Timer { interval: 4000; repeat: true; running: root.hostName !== ""; triggeredOnStart: true; onTriggered: theirs.reload() }
  onHostNameChanged: { checked = hostName === ""; hostAlive = false; if (hostName !== "") theirs.reload() }

  Component.onDestruction: Quickshell.execDetached(["rm", "-f", root.base + "/" + root.selfName + "/widget-alive"])
}
