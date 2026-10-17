import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Eye Care Breaks: EyeLeo-style break reminders.
//
// Two independent cycles, both counted from computer/shell start (or from the
// end of a big break, since a big break also resets both timers):
//   - small break: every `smallIntervalMinutes`, show a brief on-screen
//     reminder for `smallBreakSeconds`, on every monitor.
//   - big break: every `bigIntervalMinutes`, dim every screen for
//     `bigBreakMinutes`; skippable with Escape/click when `bigBreakSkippable`.
//
// Settings are read from this plugin's entry in the `plugins[]` array of
// ~/.config/omarchy/shell.json (matched by manifest id), e.g.:
//   { "id": "cvatca.eyecare", "smallIntervalMinutes": 10, "smallBreakSeconds": 30,
//     "bigIntervalMinutes": 50, "bigBreakMinutes": 10, "bigBreakSkippable": true }
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: (manifest && manifest.id) || "cvatca.eyecare"
  readonly property string pausedStateDir: home + "/.local/state/omarchy/indicators"
  readonly property string pausedStatePath: pausedStateDir + "/eyecare-paused"

  readonly property var entryConfig: {
    var plugins = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins) ? shell.shellConfig.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && plugins[i].id === root.pluginId) return plugins[i]
    }
    return ({})
  }

  function minutesFromConfig(value, fallback) {
    var n = Number(value)
    return isFinite(n) && n > 0 ? n : fallback
  }

  readonly property real smallIntervalMinutes: minutesFromConfig(entryConfig.smallIntervalMinutes, 10)
  readonly property real smallBreakSeconds: minutesFromConfig(entryConfig.smallBreakSeconds, 30)
  readonly property real bigIntervalMinutes: minutesFromConfig(entryConfig.bigIntervalMinutes, 50)
  readonly property real bigBreakMinutes: minutesFromConfig(entryConfig.bigBreakMinutes, 10)
  readonly property bool bigBreakSkippable: entryConfig.bigBreakSkippable !== undefined ? !!entryConfig.bigBreakSkippable : true
  readonly property string bigMessage: entryConfig.bigMessage || "Time for a break"

  readonly property var defaultSmallMessages: [
    "Look at something 20 feet away for a moment",
    "Blink your eyes rapidly for a few seconds",
    "Look far left, then far right",
    "Look up, then look down",
    "Roll your eyes slowly in a circle",
    "Focus on something close, then something far away",
    "Close your eyes and relax for a few seconds",
    "Look at the farthest object you can see"
  ]
  readonly property var smallMessagePool: Array.isArray(entryConfig.smallMessages) && entryConfig.smallMessages.length > 0
    ? entryConfig.smallMessages : defaultSmallMessages

  function pickSmallMessage() {
    if (entryConfig.smallMessage) return entryConfig.smallMessage
    var pool = root.smallMessagePool
    return pool[Math.floor(Math.random() * pool.length)]
  }

  property bool paused: false
  property bool pausedStateLoaded: false
  property bool smallBreakActive: false
  property bool bigBreakActive: false
  property int smallBreakRemaining: 0
  property int bigBreakRemaining: 0
  property string currentSmallMessage: ""

  readonly property bool cyclingEnabled: pausedStateLoaded && !paused

  // A flat Color.background fill reads as plain black on most dark themes,
  // since that's what a UI surface background usually is. Blending in a
  // slice of the theme's accent hue keeps the break dark enough to rest the
  // eyes while still visibly carrying the active theme's color.
  function themedOverlayColor() {
    var bg = Commons.Color.background
    var ac = Commons.Color.accent
    var mix = 0.16
    return Qt.rgba(
      bg.r * (1 - mix) + ac.r * mix,
      bg.g * (1 - mix) + ac.g * mix,
      bg.b * (1 - mix) + ac.b * mix,
      0.94
    )
  }

  function formatClock(totalSeconds) {
    var m = Math.max(0, Math.floor(totalSeconds / 60))
    var s = Math.max(0, totalSeconds % 60)
    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  function startSmallBreak() {
    if (root.bigBreakActive) return
    root.currentSmallMessage = root.pickSmallMessage()
    root.smallBreakActive = true
    root.smallBreakRemaining = Math.round(root.smallBreakSeconds)
    smallBreakCountdown.restart()
  }

  function endSmallBreak() {
    if (!root.smallBreakActive) return
    root.smallBreakActive = false
    root.smallBreakRemaining = 0
    smallBreakCountdown.stop()
  }

  function startBigBreak() {
    endSmallBreak()
    root.bigBreakActive = true
    root.bigBreakRemaining = Math.round(root.bigBreakMinutes * 60)
    bigBreakCountdown.restart()
  }

  function endBigBreak() {
    if (!root.bigBreakActive) return
    root.bigBreakActive = false
    root.bigBreakRemaining = 0
    bigBreakCountdown.stop()
    // Both cycles restart clean after any big break, small or dismissed.
    smallTimer.restart()
    bigTimer.restart()
  }

  function skipBigBreak() {
    if (!root.bigBreakActive || !root.bigBreakSkippable) return
    endBigBreak()
  }

  function setPaused(value) {
    var next = !!value
    root.paused = next
    pausedStateWriter.command = ["bash", "-lc",
      next
        ? "mkdir -p '" + root.pausedStateDir + "' && touch '" + root.pausedStatePath + "'"
        : "rm -f '" + root.pausedStatePath + "'"]
    pausedStateWriter.running = true
    if (next) {
      endSmallBreak()
      endBigBreak()
    }
    return next ? "paused" : "resumed"
  }

  function statusJson() {
    return JSON.stringify({
      paused: root.paused,
      smallBreakActive: root.smallBreakActive,
      bigBreakActive: root.bigBreakActive,
      currentSmallMessage: root.currentSmallMessage,
      smallBreakRemaining: root.smallBreakRemaining,
      bigBreakRemaining: root.bigBreakRemaining,
      smallIntervalMinutes: root.smallIntervalMinutes,
      smallBreakSeconds: root.smallBreakSeconds,
      bigIntervalMinutes: root.bigIntervalMinutes,
      bigBreakMinutes: root.bigBreakMinutes,
      bigBreakSkippable: root.bigBreakSkippable
    })
  }

  Timer {
    id: smallTimer
    interval: root.smallIntervalMinutes * 60000
    repeat: true
    running: root.cyclingEnabled && !root.bigBreakActive
    onTriggered: root.startSmallBreak()
  }

  Timer {
    id: bigTimer
    interval: root.bigIntervalMinutes * 60000
    repeat: true
    running: root.cyclingEnabled
    onTriggered: root.startBigBreak()
  }

  Timer {
    id: smallBreakCountdown
    interval: 1000
    repeat: true
    onTriggered: {
      root.smallBreakRemaining -= 1
      if (root.smallBreakRemaining <= 0) root.endSmallBreak()
    }
  }

  Timer {
    id: bigBreakCountdown
    interval: 1000
    repeat: true
    onTriggered: {
      root.bigBreakRemaining -= 1
      if (root.bigBreakRemaining <= 0) root.endBigBreak()
    }
  }

  Timer {
    id: smallBreakDotTimer
    interval: 450
    repeat: true
    running: root.smallBreakActive
    property int activeIndex: 0
    onTriggered: activeIndex = (activeIndex + 1) % 3
    onRunningChanged: if (running) activeIndex = 0
  }

  Process {
    id: pausedStateWriter
  }

  Process {
    id: pausedStateProbe
    command: ["bash", "-c", "mkdir -p '" + root.pausedStateDir + "'; [[ -f '" + root.pausedStatePath + "' ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) {
        root.paused = String(line).trim() === "yes"
        root.pausedStateLoaded = true
      }
    }
  }

  Component.onCompleted: pausedStateProbe.running = true

  IpcHandler {
    target: "eyecare"

    function status(): string { return root.statusJson() }
    function pause(): string { return root.setPaused(true) }
    function resume(): string { return root.setPaused(false) }
    function toggle(): string { return root.setPaused(!root.paused) }
    function skip(): string { root.skipBigBreak(); return "ok" }
    function triggerSmall(): string { root.startSmallBreak(); return "ok" }
    function triggerBig(): string { root.startBigBreak(); return "ok" }
  }

  // ---------------------------------------------------------- small break
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: smallPanel
      required property var modelData
      screen: modelData
      visible: root.smallBreakActive
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "omarchy-eyecare-small"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(280, parent.width - Style.space(40))
        height: Style.space(230)
        radius: Style.cornerRadius
        color: Commons.Color.background
        border.color: Commons.Color.accent
        border.width: 1
        opacity: 0.97

        MouseArea {
          anchors.fill: parent
          onClicked: root.endSmallBreak()
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.spacing.xl
          width: parent.width - Style.spacing.panelPadding * 2

          Text {
            width: parent.width
            text: root.currentSmallMessage
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.smallBreakRemaining + "s"
            color: Commons.Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            horizontalAlignment: Text.AlignHCenter
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.md

            Repeater {
              model: 3

              Rectangle {
                id: dot
                readonly property color dotColor: index === 0 ? "#7fb3ff" : index === 1 ? "#7fe0a8" : "#ffcf7f"
                readonly property bool highlighted: smallBreakDotTimer.activeIndex === index

                width: Style.space(20)
                height: Style.space(20)
                radius: Style.space(4)
                color: Qt.rgba(dotColor.r, dotColor.g, dotColor.b, highlighted ? 0.45 : 0.18)
                border.width: highlighted ? 2 : 1
                border.color: highlighted ? dotColor : Qt.rgba(dotColor.r, dotColor.g, dotColor.b, 0.35)

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }
                Behavior on border.width { NumberAnimation { duration: 200 } }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ big break
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: bigPanel
      required property var modelData
      screen: modelData
      visible: root.bigBreakActive
      anchors { top: true; bottom: true; left: true; right: true }
      color: root.themedOverlayColor()
      WlrLayershell.namespace: "omarchy-eyecare-big"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      onVisibleChanged: if (visible) Qt.callLater(function() { keyItem.forceActiveFocus() })

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.lg

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.bigMessage
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.formatClock(root.bigBreakRemaining)
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.display
        }

        Text {
          visible: root.bigBreakSkippable
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Press Esc to skip"
          color: Commons.Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body

          MouseArea {
            anchors.fill: parent
            onClicked: root.skipBigBreak()
          }
        }
      }

      Item {
        id: keyItem
        anchors.fill: parent
        focus: false
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape && root.bigBreakSkippable) {
            root.skipBigBreak()
            event.accepted = true
          }
        }
      }
    }
  }
}
