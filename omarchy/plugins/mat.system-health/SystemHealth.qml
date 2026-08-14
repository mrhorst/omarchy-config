import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "mat.system-health"

  readonly property string collectorPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/mat.system-health/system-health.py"
  property string healthText: "󰍛 …"
  property string healthTooltip: "Reading system health…"
  property string healthState: "unknown"

  function refresh() {
    if (!healthProc.running) healthProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: healthProc
    command: [root.collectorPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const value = JSON.parse(text || "{}")
          root.healthText = String(value.text || "󰍛 ?")
          root.healthTooltip = String(value.tooltip || "System health unavailable")
          root.healthState = String(value.state || "unknown")
        } catch (e) {
          root.healthText = "󰍛 ?"
          root.healthTooltip = "System health collector returned invalid data"
          root.healthState = "unknown"
        }
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.healthText
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.healthTooltip
    active: root.healthState === "warning" || root.healthState === "critical"
    onPressed: function(button) {
      if (button === Qt.RightButton) {
        Quickshell.execDetached([root.collectorPath, "--notify"])
      } else if (root.bar) {
        root.bar.run("omarchy-launch-or-focus-tui btop")
      }
    }
  }
}
