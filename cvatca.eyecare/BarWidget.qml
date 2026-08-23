import QtQuick
import qs.Ui
import qs.Commons

// Bar icon for the eyecare service: shows at a glance whether break
// reminders are running, paused, or mid-break, and opens a small panel with
// an enable/disable toggle plus the current interval settings. Reads the
// live service instance directly (same process), no IPC round trip needed.
BarWidget {
  id: root
  moduleName: "cvatca.eyecare"

  property bool popupOpen: false
  function close() { popupOpen = false }

  readonly property var eyecareService: bar?.shell?.firstPartyServiceFor("cvatca.eyecare")
  readonly property bool running: eyecareService ? eyecareService.cyclingEnabled : false
  readonly property bool smallActive: eyecareService ? eyecareService.smallBreakActive : false
  readonly property bool bigActive: eyecareService ? eyecareService.bigBreakActive : false

  readonly property color glyphColor: bigActive ? Color.urgent
    : smallActive ? Color.accent
    : running ? (bar ? bar.barForeground : Color.foreground)
    : Color.muted

  readonly property string statusLine: {
    if (!eyecareService) return "Eye care breaks"
    if (bigActive) return "Big break in progress"
    if (smallActive) return "Small break in progress"
    if (!running) return "Paused"
    return "Running"
  }

  implicitWidth: barSize
  implicitHeight: barSize

  Text {
    anchors.centerIn: parent
    text: "󰈈"
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.icon
    color: root.glyphColor
    Behavior on color { ColorAnimation { duration: 160 } }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.bar) root.bar.hideTooltip(root)
      root.popupOpen = !root.popupOpen
    }
    onEntered: if (root.bar && !root.popupOpen) root.bar.showTooltip(root, root.statusLine)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.spacing.md

      Text {
        width: parent.width
        text: "Eye Care Breaks"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Toggle {
        width: parent.width
        label: root.running ? "Breaks enabled" : "Breaks paused"
        description: root.statusLine
        checked: root.running
        onClicked: if (root.eyecareService) root.eyecareService.setPaused(root.running)
      }

      PanelSeparator {}

      PanelSectionHeader { text: "Settings" }

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: root.eyecareService ? [
            { label: "Small break", value: root.eyecareService.smallIntervalMinutes + " min → " + root.eyecareService.smallBreakSeconds + "s reminder" },
            { label: "Big break", value: root.eyecareService.bigIntervalMinutes + " min → " + root.eyecareService.bigBreakMinutes + " min dim" },
            { label: "Skippable", value: root.eyecareService.bigBreakSkippable ? "Yes (Esc or click)" : "No" }
          ] : []

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              width: Style.space(88)
              text: modelData.label
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width - Style.space(88) - Style.spacing.sm
              text: modelData.value
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
