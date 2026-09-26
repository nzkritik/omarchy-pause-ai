import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// `Panel` owns only the open/close state. The visible surface is the
// KeyboardPanel below, bound to `open: root.opened`: content placed directly
// in the Panel item would render nowhere, since the host Loader is invisible.
Panel {
  id: root

  moduleName: "nzkritik.pause-ai"
  ipcTarget: moduleName
  manageIpc: false          // this file provides its own IpcHandler instead

  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool paused: service ? service.paused : false

  readonly property var presets: [
    { label: "5 min", minutes: 5 }, { label: "10 min", minutes: 10 },
    { label: "15 min", minutes: 15 }, { label: "30 min", minutes: 30 },
    { label: "1 hour", minutes: 60 }, { label: "Until resumed", minutes: 0 }
  ]

  readonly property string headline: {
    if (!service) return "Starting…"
    if (service.lastError !== "") return service.lastError
    if (paused)
      return service.until > 0 ? "Paused — resumes in " + service.formatRemaining(service.remaining)
                               : "Paused until you resume"
    var n = service.running
    return n === 0 ? "No AI agents running" : n === 1 ? "1 AI agent running" : n + " AI agents running"
  }

  function pauseFor(minutes) {
    if (!service) return
    service.pause(minutes)
    root.close()
  }

  onOpenedChanged: if (opened && service) service.refresh()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function pause(minutes: int): string {
      if (!root.service) return "no service"
      root.service.pause(minutes)
      return "ok"
    }
    function resume(): string {
      if (!root.service) return "no service"
      root.service.resume()
      return "ok"
    }
    function status(): string {
      if (!root.service) return "{}"
      return JSON.stringify({
        paused: root.service.paused, until: root.service.until,
        remaining: root.service.remaining, frozen: root.service.frozen,
        running: root.service.running, agents: root.service.agents,
        error: root.service.lastError
      })
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    // Sized to what is in it. contentWidth/contentHeight are the whole card,
    // padding and border included, so the fitting helpers add the inset.
    // The width follows the widest row that cannot wrap (the preset buttons,
    // an agent line); the wrapping text below opts out of driving it.
    contentWidth: panel.fittedContentWidth(
        Math.max(Style.space(300), body.implicitWidth) + panel.padding * 2 + Style.space(2),
        Style.space(480))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: "Pause AI"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          font.bold: true
          font.letterSpacing: 0.6
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          height: 1
          color: Util.alpha(root.foreground, 0.16)
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.preferredWidth: 0          // wraps to the panel; never widens it
        textFormat: Text.PlainText
        text: root.headline
        color: root.paused ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.space(14)
        wrapMode: Text.Wrap
      }

      Button {
        Layout.fillWidth: true
        visible: root.paused
        text: "Resume now"
        bordered: true
        onClicked: { if (root.service) root.service.resume(); root.close() }
      }

      Text {
        textFormat: Text.PlainText
        text: root.paused ? "Change the pause" : "Pause all agents for"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }

      GridLayout {
        id: presetGrid
        // Equal columns, each wide enough for the longest label with its
        // padding; the panel's width follows from this.
        property real widest: 0
        Layout.fillWidth: true
        Layout.minimumWidth: widest * columns + columnSpacing * (columns - 1)
        columns: 3
        uniformCellWidths: true
        columnSpacing: Style.space(6)
        rowSpacing: Style.space(6)
        Repeater {
          model: root.presets
          Button {
            required property var modelData
            Layout.fillWidth: true
            onImplicitWidthChanged: presetGrid.widest = Math.max(presetGrid.widest, implicitWidth)
            Component.onCompleted: presetGrid.widest = Math.max(presetGrid.widest, implicitWidth)
            text: modelData.label
            bordered: true
            onClicked: root.pauseFor(modelData.minutes)
          }
        }
      }

      Text {
        visible: root.service && root.service.agents.length > 0
        textFormat: Text.PlainText
        text: "Agents"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }

      Repeater {
        model: root.service ? root.service.agents : []
        RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: modelData.name + "  ·  pid " + modelData.pid
                  + (modelData.children > 0 ? "  ·  +" + modelData.children : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.stopped ? "paused" : "running"
            color: modelData.stopped ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
          }
        }
      }

      Text {
        Layout.fillWidth: true
        Layout.preferredWidth: 0          // wraps to the panel; never widens it
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: "Agents are frozen where they are, with everything they started, and pick up "
              + "again on resume. A request to an AI service that is in flight may time out "
              + "if the pause is long."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
      }
    }
  }
}
