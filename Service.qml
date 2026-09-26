import QtQuick
import Quickshell
import Quickshell.Io

// Pause AI state and control.
//
// All the work is done by bin/pause-ai, run unprivileged with a closed
// environment. The pause itself lives in that tool's state file, not here, so
// a shell restart during a pause neither loses it nor thaws anything: on start
// this service reads the state back and carries on (ending a timed pause
// whose time ran out while the shell was down).
Item {
  id: root

  property var shell: null

  // Pushed in from the bar widget's settings: extra command names to treat as
  // agents, already validated there.
  property var extraAgents: []

  // ── State, as last reported by the tool ───────────────────────────────────
  property bool paused: false
  property real until: 0            // unix seconds; 0 = until resumed
  property int frozen: 0            // processes currently held
  property var agents: []           // [{pid, name, stopped, children}]
  property bool ready: false
  property string lastError: ""
  property real now: Date.now() / 1000

  readonly property int running: {
    var n = 0
    for (var i = 0; i < agents.length; i++) if (!agents[i].stopped) n++
    return n
  }
  readonly property int remaining: paused && until > 0 ? Math.max(0, Math.round(until - now)) : 0

  function formatRemaining(s) {
    if (s >= 3600) return Math.floor(s / 3600) + ":" + pad(Math.floor(s % 3600 / 60)) + ":" + pad(s % 60)
    return Math.floor(s / 60) + ":" + pad(s % 60)
  }
  function pad(n) { return (n < 10 ? "0" : "") + n }

  // ── Actions ───────────────────────────────────────────────────────────────
  // minutes <= 0 pauses until resumed. Pausing while paused only changes the
  // end time; everything already frozen stays frozen.
  function pause(minutes) {
    var args = ["pause"]
    if (minutes > 0) args.push("--until", String(Math.round(Date.now() / 1000 + minutes * 60)))
    else if (paused && until > 0) args.push("--until", "0")    // a timed pause becomes open-ended
    run(args)
  }
  function resume() { run(["resume"]) }
  function toggle() { if (paused) resume(); else pause(0) }
  function refresh() { run(["status"]) }

  // ── Running the tool ──────────────────────────────────────────────────────
  // One command at a time, in order: a click during a sweep waits its turn
  // rather than racing it.
  property var queue: []

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    return u.indexOf("file://") === 0 ? u.substring(7) : u
  }
  readonly property string tool: pluginDir + "bin/pause-ai"

  function run(args) {
    var full = ["/usr/bin/python3", "-I", tool].concat(args)
    for (var i = 0; i < extraAgents.length; i++) full.push("--name", extraAgents[i])
    // a status or sweep already waiting is superseded by anything newer
    var q = queue.filter(function (c) { return c[3] !== "status" })
    q.push(full)
    queue = q
    next()
  }

  function next() {
    if (proc.running || queue.length === 0) return
    var q = queue.slice()
    proc.command = q.shift()
    queue = q
    proc.running = true
  }

  Process {
    id: proc
    clearEnvironment: true
    environment: ({ PATH: "/usr/bin", HOME: null, LANG: null })
    stdout: StdioCollector {
      onStreamFinished: {
        var cmd = proc.command[3]
        var data = null
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (!data) {
          root.lastError = "pause-ai gave no answer"
        } else if (data.error) {
          root.lastError = String(data.error)
        } else {
          root.lastError = ""
          if (cmd === "status") root.apply(data)
        }
        // every action is followed by a fresh status, so the bar never guesses
        if (cmd !== "status") root.queue = root.queue.concat([["/usr/bin/python3", "-I", root.tool, "status"]
            .concat(root.nameArgs())])
      }
    }
    onExited: root.next()
  }

  function nameArgs() {
    var out = []
    for (var i = 0; i < extraAgents.length; i++) out.push("--name", extraAgents[i])
    return out
  }

  function apply(data) {
    paused = data.paused === true
    until = paused && Number(data.until) > 0 ? Number(data.until) : 0
    frozen = Number(data.frozen) || 0
    agents = Array.isArray(data.agents) ? data.agents : []
    now = Date.now() / 1000
    ready = true
  }

  // ── Timers ────────────────────────────────────────────────────────────────
  // While paused: freeze any agent that starts in the meantime.
  Timer {
    interval: 4000
    repeat: true
    running: root.paused
    onTriggered: if (root.queue.length === 0) root.run(["pause"])
  }

  // While running: keep the agent count in the tooltip current.
  Timer {
    interval: 15000
    repeat: true
    running: !root.paused
    onTriggered: if (root.queue.length === 0) root.refresh()
  }

  // The countdown, and the end of a timed pause.
  Timer {
    interval: 1000
    repeat: true
    running: root.paused && root.until > 0
    onTriggered: {
      root.now = Date.now() / 1000
      if (root.now >= root.until && root.queue.length === 0) root.resume()
    }
  }

  onExtraAgentsChanged: refresh()
  Component.onCompleted: refresh()
}
