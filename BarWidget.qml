import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sun or moon glyph plus the countdown to the next sunrise or sunset.
//
// All astronomy lives in bin/daylight.py (python3 stdlib, no network). This
// widget runs it once a minute and keeps the JSON; the countdown ticks in QML
// between runs so the bar never waits on a process.
BarWidget {
  id: root
  moduleName: "nixfred.daylight"
  property var anchorItem: button

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }
  readonly property bool showCountdown: String(setting("showCountdown", true)) !== "false"
  readonly property string latSetting: String(setting("lat", "")).trim()
  readonly property string lonSetting: String(setting("lon", "")).trim()
  readonly property string placeSetting: String(setting("place", "")).trim()

  readonly property color foreground: bar ? bar.foreground : Color.foreground

  property var eph: null
  property string lastError: ""
  property double nowMs: Date.now()

  function scriptPath() {
    return decodeURIComponent(String(Qt.resolvedUrl("bin/daylight.py")).replace(/^file:\/\//, ""))
  }

  function command() {
    var c = ["python3", scriptPath()]
    if (latSetting !== "" && lonSetting !== "" && isFinite(Number(latSetting)) && isFinite(Number(lonSetting)))
      c = c.concat(["--lat", latSetting, "--lon", lonSetting])
    if (placeSetting !== "") c = c.concat(["--place", placeSetting])
    return c
  }

  function refresh() {
    if (poll.running) return
    poll.command = command()
    poll.running = true
  }

  onLatSettingChanged: refresh()
  onLonSettingChanged: refresh()
  onPlaceSettingChanged: refresh()

  Process {
    id: poll
    property bool gotOutput: false
    onStarted: gotOutput = false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(text) } catch (e) { root.lastError = "bad JSON from daylight.py"; return }
        poll.gotOutput = true
        if (!d || !d.ok) { root.lastError = d && d.error ? d.error : "daylight.py failed"; return }
        root.lastError = ""
        root.eph = d
        root.nowMs = Date.now()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("daylight:", text.trim())
    }
    onExited: function(code) {
      if (code === 127) root.lastError = "python3 not found: Daylight needs it"
      else if (code !== 0 && root.lastError === "") root.lastError = "daylight.py exited " + code
    }
    // A missing binary never emits exited on Quickshell 0.3.x; running just
    // flips back to false. Treat "stopped with no output" as a failure.
    onRunningChanged: if (!running && !gotOutput && root.lastError === "") root.lastError = "daylight.py produced no output (python3 missing?)"
  }

  Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { interval: 15000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

  function fmtDur(sec) {
    sec = Math.max(0, Math.round(sec))
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60)
    return h > 0 ? h + "h" + (m < 10 ? "0" : "") + m : m + "m"
  }

  readonly property bool sunUp: eph ? eph.sun.up : true
  readonly property string nextKind: eph ? (eph.sun.next || "") : ""
  readonly property double nextAt: eph && eph.sun.nextAt ? eph.sun.nextAt : 0
  readonly property string countdown: nextAt > 0 ? fmtDur(nextAt - nowMs / 1000) : "--"

  // Nerd Font MDI glyphs: weather-sunny, weather-night.
  readonly property string glyph: lastError !== "" ? "\u{F0026}" : (sunUp ? "\u{F0599}" : "\u{F0594}")
  readonly property string arrow: nextKind === "sunrise" ? "↑" : "↓"

  readonly property real contentWidth: Style.space(showCountdown ? 74 : 26)
  implicitWidth: vertical ? barSize : contentWidth
  implicitHeight: vertical ? contentWidth : barSize

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    active: false
    useActiveColor: false
    tooltipText: {
      if (root.lastError !== "") return "Daylight: " + root.lastError
      if (!root.eph) return "Daylight: computing"
      var t = Qt.formatDateTime(new Date(root.nextAt * 1000), "HH:mm")
      return "Daylight: " + root.nextKind + " " + t + " (in " + root.countdown + ")  sun "
             + root.eph.sun.elevation.toFixed(1) + "°  moon "
             + Math.round(root.eph.moon.illumination * 100) + "%"
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(4)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: root.lastError !== "" ? Color.urgent : (root.sunUp ? Color.accent : root.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        visible: root.showCountdown
        anchors.verticalCenter: parent.verticalCenter
        text: root.arrow + root.countdown
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    onPressed: function(code) {
      if (root.bar) root.bar.hideTooltip(root)
      root.toggle()
    }
  }

  readonly property bool opened: panel.opened
  function open() { panel.controller.show(); refresh() }
  function close() { panel.controller.hide() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  readonly property bool popoutSwitchClosing: false

  // omarchy-shell nixfred.daylight toggle|open|close|json
  IpcHandler {
    target: "nixfred.daylight"
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function json(): string { return root.eph ? JSON.stringify(root.eph) : (root.lastError || "no data") }
  }

  DaylightPanel {
    id: panel
    widget: root
  }
}
