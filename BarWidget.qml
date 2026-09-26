import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Left click: pause every AI agent until resumed, or resume.
// Right click: the panel with timed pauses.
BarWidget {
  id: root
  moduleName: "nzkritik.pause-ai"

  readonly property var shell: bar && bar.shell ? bar.shell : null
  readonly property var svc: shell ? shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent

  readonly property bool paused: svc ? svc.paused : false
  readonly property int running: svc ? svc.running : 0

  // 󰏤 pause while paused, 󰙴 the AI sparkle otherwise (dimmed when no agent
  // runs). Not the robot: omarchy.agents already uses that on the same bar.
  readonly property string glyph: paused ? "\u{F03E4}" : "\u{F0674}"
  readonly property color glyphColor: {
    if (!svc || svc.lastError !== "") return urgent
    if (paused) return Color.accent
    return running > 0 ? foreground : Qt.darker(foreground, 1.6)
  }

  readonly property string barTooltip: {
    if (!svc) return "Pause AI — starting…"
    if (svc.lastError !== "") return "Pause AI — " + svc.lastError
    if (paused) {
      var held = svc.frozen === 1 ? "1 process held" : svc.frozen + " processes held"
      var left = svc.until > 0 ? "resumes in " + svc.formatRemaining(svc.remaining)
                               : "until you resume"
      return "AI agents paused — " + left + "\n" + held
             + "\nLeft click to resume · right click for options"
    }
    var what = running === 0 ? "No AI agents running"
             : running === 1 ? "1 AI agent running" : running + " AI agents running"
    return what + "\nLeft click to pause · right click for timed pauses"
  }

  function injectPanel() {
    if (!svc || !panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.service = root.svc
  }

  function loadPanel() {
    if (!svc || panelLoader.status !== Loader.Null) return
    panelLoader.setSource(Qt.resolvedUrl("Panel.qml"), {
      bar: root.bar, settings: root.settings, anchorItem: button,
      hostWidget: root, service: root.svc
    })
  }

  // The service starts before shell.json is read, so settings are pushed in.
  function pushSettings() {
    if (!svc) return
    var raw = String(root.setting("extraAgents", "")).trim()
    var names = []
    var parts = raw === "" ? [] : raw.split(/[\s,]+/)
    for (var i = 0; i < parts.length && names.length < 32; i++)
      if (/^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$/.test(parts[i])) names.push(parts[i])
    if (JSON.stringify(names) !== JSON.stringify(svc.extraAgents)) svc.extraAgents = names
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: loadPanel()
  onBarChanged: injectPanel()
  onSettingsChanged: { injectPanel(); pushSettings() }
  onSvcChanged: { loadPanel(); injectPanel(); pushSettings() }

  Loader {
    id: panelLoader
    active: root.svc !== null
    visible: false
    onLoaded: root.injectPanel()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.barTooltip
    iconComponent: Component {
      Item {
        implicitWidth: glyphText.implicitWidth
        implicitHeight: glyphText.implicitHeight
        Text {
          id: glyphText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.glyph
          color: root.glyphColor
          font.family: Style.fontFamily
          font.pixelSize: Style.bar.iconFont
          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggle()
      else if (root.svc) root.svc.toggle()
    }
  }
}
