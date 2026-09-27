import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// The sun and moon cockpit. Law 17: one screen, no Flickable, no ScrollView.
// Width is the remedy, never height: arc and event grid on the left, day
// length, sun-now and moon on a fixed right rail. Detail lives in tooltips.
Panel {
  id: panel
  moduleName: "nixfred.daylight"
  manageIpc: false

  required property var widget
  readonly property var d: widget.eph
  readonly property double nowS: widget.nowMs / 1000

  readonly property color foreground: widget.bar ? widget.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Util.alpha(foreground, 0.10)
  readonly property color accent: Color.accent
  readonly property color gold: "#ffb347"
  readonly property color blue: "#5b7cfa"
  readonly property string fontFamily: widget.bar ? widget.bar.fontFamily : Style.font.family

  readonly property int panelWidth: Style.space(1120)
  readonly property int railWidth: Style.space(360)

  function hm(t) { return t ? Qt.formatDateTime(new Date(t * 1000), "HH:mm") : "--:--" }
  function hms(t) { return t ? Qt.formatDateTime(new Date(t * 1000), "HH:mm:ss") : "--" }
  function dayDate(t) { return t ? Qt.formatDateTime(new Date(t * 1000), "ddd MMM d, HH:mm") : "--" }
  function dur(sec) {
    if (sec === null || sec === undefined) return "--"
    sec = Math.round(Math.abs(sec))
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
    return h + "h " + (m < 10 ? "0" : "") + m + "m " + (s < 10 ? "0" : "") + s + "s"
  }
  function until(t) {
    if (!t) return "--"
    var s = t - nowS
    if (s < 0) return "passed"
    var dd = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
    return dd > 0 ? dd + "d " + h + "h" : (h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + "m")
  }
  function signed(sec) {
    if (sec === null || sec === undefined) return "--"
    var m = Math.floor(Math.abs(sec) / 60), s = Math.abs(sec) % 60
    return (sec < 0 ? "-" : "+") + m + "m " + (s < 10 ? "0" : "") + s + "s"
  }

  // ------------------------------------------------------------ building blocks
  component Caption: Text {
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    font.bold: true
  }

  component Stat: Rectangle {
    id: stat
    property string label: ""
    property string value: ""
    property string sub: ""
    property string tip: ""
    property color tint: panel.foreground
    Layout.fillWidth: true
    implicitHeight: Style.space(52)
    radius: Style.cornerRadius
    color: Util.alpha(tint, 0.07)
    border.width: 0
    Rectangle { width: Style.space(3); height: parent.height - Style.space(12); anchors.verticalCenter: parent.verticalCenter; color: stat.tint; opacity: 0.8; border.width: 0; radius: width / 2 }
    Column {
      anchors.left: parent.left; anchors.leftMargin: Style.space(10)
      anchors.right: parent.right; anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)
      Text { text: stat.label; color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
      Row {
        spacing: Style.space(6)
        Text { text: stat.value; color: panel.foreground; font.family: panel.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
        Text { text: stat.sub; color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.caption; anchors.baseline: parent.children[0].baseline }
      }
    }
    MouseArea { id: statMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    PanelToolTip { visible: stat.tip !== "" && statMouse.containsMouse; text: stat.tip; fontFamily: panel.fontFamily }
  }

  KeyboardPanel {
    id: kpanel
    anchorItem: panel.widget.anchorItem
    owner: panel.widget
    bar: panel.widget.bar
    open: panel.opened
    focusTarget: keyCatcher
    contentWidth: kpanel.fittedContentWidth(panel.panelWidth)
    contentHeight: kpanel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: panel.widget.close()

      ColumnLayout {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ------------------------------------------------------ header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)
          Text {
            text: panel.widget.glyph
            color: panel.widget.lastError !== "" ? Color.urgent : panel.accent
            font.family: panel.fontFamily
            font.pixelSize: Style.font.subtitle
          }
          Text { text: "DAYLIGHT"; color: panel.foreground; font.family: panel.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; font.letterSpacing: 2 }
          Text {
            text: panel.d ? panel.d.place + "  " + panel.d.lat.toFixed(3) + ", " + panel.d.lon.toFixed(3) + "  " + panel.d.tz : ""
            color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          Item { Layout.fillWidth: true }
          Text {
            visible: panel.widget.lastError !== ""
            text: panel.widget.lastError
            color: Color.urgent; font.family: panel.fontFamily; font.pixelSize: Style.font.bodySmall
          }
          Text {
            text: panel.d ? (panel.d.sun.next === "sunrise" ? "↑ sunrise in " : "↓ sunset in ") + panel.until(panel.d.sun.nextAt) + "  at " + panel.hm(panel.d.sun.nextAt) : ""
            color: panel.foreground; font.family: panel.fontFamily; font.pixelSize: Style.font.body; font.bold: true
          }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: panel.faint; border.width: 0 }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(14)

          // ================================================ left: arc + events
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(8)

            RowLayout {
              Layout.fillWidth: true
              Caption { text: "SOLAR ELEVATION  TODAY" }
              Item { Layout.fillWidth: true }
              Repeater {
                model: [
                  { "c": panel.gold, "t": "golden  -4° to 6°" },
                  { "c": panel.blue, "t": "blue  -6° to -4°" },
                  { "c": panel.accent, "t": "sun now" }
                ]
                delegate: Row {
                  required property var modelData
                  spacing: Style.space(4)
                  Rectangle { width: Style.space(8); height: width; radius: width / 2; color: modelData.c; border.width: 0; anchors.verticalCenter: parent.verticalCenter }
                  Text { text: modelData.t; color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.caption }
                }
              }
            }

            Canvas {
              id: arc
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: Style.space(230)
              renderStrategy: Canvas.Cooperative
              property var eph: panel.d
              property double now: panel.nowS
              onEphChanged: requestPaint()
              onNowChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var W = width, H = height
                var data = eph
                if (!data || !data.arc) return
                var a = data.arc, mid = data.midnight
                var top = Math.max(30, Math.ceil((data.today.noonElev + 8) / 10) * 10)
                var bot = Math.min(-20, Math.floor((Math.min.apply(null, a) - 2) / 10) * 10)
                bot = Math.max(bot, -90)
                var padB = 16
                function X(i) { return i / (a.length - 1) * W }
                function Xt(t) { return (t - mid) / 86400 * W }
                function Y(e) { return (top - e) / (top - bot) * (H - padB) }
                var fg = String(panel.foreground), ac = String(panel.accent)

                // Time bands by sun elevation: night, twilights, blue, golden, day.
                for (var i = 0; i < a.length - 1; i++) {
                  var e = (a[i] + a[i + 1]) / 2, col = null, al = 0
                  if (e >= 6) { col = ac; al = 0.07 }
                  else if (e >= -4) { col = String(panel.gold); al = 0.30 }
                  else if (e >= -6) { col = String(panel.blue); al = 0.38 }
                  else if (e >= -12) { col = String(panel.blue); al = 0.14 }
                  else if (e >= -18) { col = String(panel.blue); al = 0.06 }
                  if (col) {
                    ctx.globalAlpha = al; ctx.fillStyle = col
                    ctx.fillRect(X(i), 0, X(i + 1) - X(i) + 0.5, H - padB)
                  }
                }
                ctx.globalAlpha = 1

                // Grid: horizon and every 30 deg.
                ctx.lineWidth = 1
                for (var g = Math.ceil(bot / 30) * 30; g <= top; g += 30) {
                  ctx.strokeStyle = fg; ctx.globalAlpha = g === 0 ? 0.55 : 0.12
                  ctx.beginPath(); ctx.moveTo(0, Y(g)); ctx.lineTo(W, Y(g)); ctx.stroke()
                  if (Y(g) > H - padB - 12) continue
                  ctx.globalAlpha = 0.5; ctx.fillStyle = fg
                  ctx.font = "10px sans-serif"
                  ctx.fillText((g > 0 ? "+" : "") + g + "°", 3, Y(g) - 3)
                }
                // Hour ticks.
                ctx.globalAlpha = 0.5; ctx.fillStyle = fg
                for (var h = 0; h <= 24; h += 3) {
                  var x = h / 24 * W
                  ctx.globalAlpha = 0.12; ctx.strokeStyle = fg
                  ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H - padB); ctx.stroke()
                  ctx.globalAlpha = 0.6
                  var lbl = (h < 10 ? "0" : "") + h + ":00"
                  var tx = h === 0 ? x + 2 : (h === 24 ? x - 32 : x - 15)
                  ctx.fillText(lbl, tx, H - 3)
                }

                // Elevation curve: bright above horizon, faint below.
                ctx.globalAlpha = 1; ctx.lineWidth = 2.2
                for (var j = 0; j < a.length - 1; j++) {
                  ctx.strokeStyle = a[j] > -0.833 ? ac : fg
                  ctx.globalAlpha = a[j] > -0.833 ? 1 : 0.35
                  ctx.beginPath(); ctx.moveTo(X(j), Y(a[j])); ctx.lineTo(X(j + 1), Y(a[j + 1])); ctx.stroke()
                }

                // Sunrise / noon / sunset markers.
                ctx.globalAlpha = 0.9; ctx.fillStyle = fg; ctx.font = "bold 11px sans-serif"
                var marks = [[data.today.sunrise, "↑ " + panel.hm(data.today.sunrise)],
                             [data.today.noon, "noon " + panel.hm(data.today.noon) + "  " + data.today.noonElev.toFixed(1) + "°"],
                             [data.today.sunset, "↓ " + panel.hm(data.today.sunset)]]
                for (var k = 0; k < marks.length; k++) {
                  if (!marks[k][0]) continue
                  var mx = Xt(marks[k][0])
                  var my = k === 1 ? Y(data.today.noonElev) - 10 : Y(0) - 8
                  var tw = ctx.measureText(marks[k][1]).width
                  ctx.fillText(marks[k][1], Math.max(2, Math.min(W - tw - 2, mx - tw / 2)), Math.max(12, my))
                }

                // Sun now.
                var nx = Xt(now), ne = data.sun.elevation
                if (nx >= 0 && nx <= W) {
                  ctx.globalAlpha = 0.35; ctx.strokeStyle = ac; ctx.lineWidth = 1
                  ctx.beginPath(); ctx.moveTo(nx, 0); ctx.lineTo(nx, H - padB); ctx.stroke()
                  ctx.globalAlpha = 0.25; ctx.fillStyle = ac
                  ctx.beginPath(); ctx.arc(nx, Y(ne), 13, 0, Math.PI * 2); ctx.fill()
                  ctx.globalAlpha = 1
                  ctx.beginPath(); ctx.arc(nx, Y(ne), 6, 0, Math.PI * 2); ctx.fill()
                  ctx.fillStyle = fg; ctx.font = "bold 11px sans-serif"
                  var nl = "now " + ne.toFixed(1) + "°"
                  var nw = ctx.measureText(nl).width
                  var lx = nx + 16 + nw > W ? nx - 16 - nw : nx + 16
                  ctx.fillText(nl, lx, Math.min(H - padB - 4, Math.max(12, Y(ne) + 4)))
                }
              }
            }

            Caption { text: "EVENTS  TODAY" }
            GridLayout {
              Layout.fillWidth: true
              columns: 6
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(6)
              Stat { label: "astro dawn"; value: panel.hm(panel.d ? panel.d.today.astroDawn : 0); tint: panel.blue; tip: "Sun at -18°. Sky fully dark before this." }
              Stat { label: "nautical dawn"; value: panel.hm(panel.d ? panel.d.today.nauticalDawn : 0); tint: panel.blue; tip: "Sun at -12°. Horizon becomes visible at sea." }
              Stat { label: "civil dawn"; value: panel.hm(panel.d ? panel.d.today.civilDawn : 0); tint: panel.blue; tip: "Sun at -6°. Enough light for most outdoor work. Blue hour runs from here." }
              Stat { label: "blue hr ends"; value: panel.hm(panel.d ? panel.d.today.blueAmEnd : 0); tint: panel.blue; tip: "Sun at -4°. Blue hour (-6° to -4°) ends, golden hour begins." }
              Stat { label: "sunrise"; value: panel.hm(panel.d ? panel.d.today.sunrise : 0); tint: panel.gold; sub: panel.d ? panel.signed(panel.d.today.sunrise - panel.d.yesterday.sunrise - 86400) : ""; tip: "Upper limb on the horizon (-0.833° incl. refraction). Sub: shift vs yesterday." }
              Stat { label: "golden AM ends"; value: panel.hm(panel.d ? panel.d.today.goldenAmEnd : 0); tint: panel.gold; tip: "Sun climbs past 6°; morning golden hour is over." }
              Stat { label: "solar noon"; value: panel.hm(panel.d ? panel.d.today.noon : 0); tint: panel.accent; sub: panel.d ? panel.d.today.noonElev.toFixed(1) + "°" : ""; tip: "Sun at its highest. Sub: peak elevation." }
              Stat { label: "golden PM starts"; value: panel.hm(panel.d ? panel.d.today.goldenPmStart : 0); tint: panel.gold; tip: "Sun drops below 6°; evening golden hour begins." }
              Stat { label: "sunset"; value: panel.hm(panel.d ? panel.d.today.sunset : 0); tint: panel.gold; sub: panel.d ? panel.signed(panel.d.today.sunset - panel.d.yesterday.sunset - 86400) : ""; tip: "Upper limb touches the horizon. Sub: shift vs yesterday." }
              Stat { label: "blue hr starts"; value: panel.hm(panel.d ? panel.d.today.bluePmStart : 0); tint: panel.blue; tip: "Sun at -4°. Evening blue hour until civil dusk." }
              Stat { label: "civil dusk"; value: panel.hm(panel.d ? panel.d.today.civilDusk : 0); tint: panel.blue; tip: "Sun at -6°. Streetlights time." }
              Stat { label: "astro dusk"; value: panel.hm(panel.d ? panel.d.today.astroDusk : 0); tint: panel.blue; sub: panel.d ? "n " + panel.hm(panel.d.today.nauticalDusk) : ""; tip: "Sun at -18°: true night. Sub: nautical dusk (-12°)." }
            }
          }

          // ================================================ right rail
          ColumnLayout {
            Layout.preferredWidth: panel.railWidth
            Layout.maximumWidth: panel.railWidth
            Layout.alignment: Qt.AlignTop
            spacing: Style.space(8)

            Caption { text: "DAY LENGTH" }
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(10)
              Text {
                text: panel.d ? panel.dur(panel.d.today.dayLength) : "--"
                color: panel.foreground; font.family: panel.fontFamily; font.pixelSize: Style.font.title; font.bold: true
              }
              Text {
                text: panel.d ? panel.signed(panel.d.dayDelta) : ""
                color: panel.d && panel.d.dayDelta < 0 ? panel.blue : panel.gold
                font.family: panel.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true }
                PanelToolTip { visible: dm.containsMouse; text: "Change vs yesterday (" + (panel.d ? panel.dur(panel.d.yesterday.dayLength) : "") + ")"; fontFamily: panel.fontFamily }
              }
            }
            GridLayout {
              Layout.fillWidth: true
              columns: 2
              columnSpacing: Style.space(6); rowSpacing: Style.space(6)
              Stat { label: "tomorrow"; value: panel.d ? panel.signed(panel.d.dayDeltaTomorrow) : "--"; sub: panel.d ? panel.hm(panel.d.tomorrow.sunrise) + " to " + panel.hm(panel.d.tomorrow.sunset) : ""; tip: "Day length change tomorrow, and tomorrow's sunrise to sunset." }
              Stat { label: "daylight left"; value: panel.d ? (panel.d.sun.up ? panel.until(panel.d.today.sunset) : "sun down") : "--"; tint: panel.gold; tip: "Time until today's sunset." }
            }

            Caption { text: "SUN NOW" }
            GridLayout {
              Layout.fillWidth: true
              columns: 2
              columnSpacing: Style.space(6); rowSpacing: Style.space(6)
              Stat { label: "elevation"; value: panel.d ? panel.d.sun.elevation.toFixed(2) + "°" : "--"; tint: panel.accent; tip: "Apparent altitude with NOAA refraction. Negative is below the horizon." }
              Stat { label: "azimuth"; value: panel.d ? panel.d.sun.azimuth.toFixed(1) + "°" : "--"; tint: panel.accent; tip: "Compass bearing, clockwise from true north." }
              Stat { label: "declination"; value: panel.d ? panel.d.sun.declination.toFixed(2) + "°" : "--"; tip: "Sun's angle north (+) or south (-) of the celestial equator." }
              Stat { label: "equation of time"; value: panel.d ? panel.d.sun.eqTimeMin.toFixed(2) + " min" : "--"; tip: "Sundial time minus clock (mean) time." }
            }

            Caption { text: "MOON" }
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(12)
              Canvas {
                id: moonGlyph
                Layout.preferredWidth: Style.space(84)
                Layout.preferredHeight: Style.space(84)
                property var m: panel.d ? panel.d.moon : null
                onMChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  if (!m) return
                  var r = Math.min(width, height) / 2 - 4, cx = width / 2, cy = height / 2
                  var lit = String(panel.foreground), ac = String(panel.accent)
                  // halo
                  ctx.globalAlpha = 0.10 + 0.15 * m.illumination; ctx.fillStyle = ac
                  ctx.beginPath(); ctx.arc(cx, cy, r + 4, 0, Math.PI * 2); ctx.fill()
                  // dark disc
                  ctx.globalAlpha = 0.14; ctx.fillStyle = lit
                  ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fill()
                  // lit part: a half disc on the sunward side plus a terminator
                  // ellipse (lit for gibbous, dark for crescent).
                  var k = m.illumination
                  var right = m.waxing          // northern hemisphere view
                  ctx.globalAlpha = 0.95; ctx.fillStyle = lit
                  ctx.beginPath()
                  ctx.arc(cx, cy, r, -Math.PI / 2, Math.PI / 2, !right)
                  var rx = Math.abs(1 - 2 * k) * r
                  // back along the terminator
                  ctx.save()
                  ctx.translate(cx, cy); ctx.scale(Math.max(rx, 0.01) / r, 1)
                  ctx.arc(0, 0, r, Math.PI / 2, -Math.PI / 2, (k > 0.5) ? !right : right)
                  ctx.restore()
                  ctx.closePath(); ctx.fill()
                }
                MouseArea { id: mm; anchors.fill: parent; hoverEnabled: true }
                PanelToolTip { visible: mm.containsMouse; text: panel.d ? "Age " + panel.d.moon.ageDays.toFixed(1) + " d of 29.53. Altitude " + panel.d.moon.altitude.toFixed(1) + "° now." : ""; fontFamily: panel.fontFamily }
              }
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                  text: panel.d ? panel.d.moon.phase : "--"
                  color: panel.foreground; font.family: panel.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true
                }
                Text {
                  text: panel.d ? (panel.d.moon.illumination * 100).toFixed(1) + "% lit  " + (panel.d.moon.illumination >= panel.d.moon.illumYesterday ? "↑" : "↓") + " " + Math.abs((panel.d.moon.illumination - panel.d.moon.illumYesterday) * 100).toFixed(1) + "%/day" : ""
                  color: panel.accent; font.family: panel.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                }
                Text {
                  text: panel.d ? "age " + panel.d.moon.ageDays.toFixed(1) + " d  alt " + panel.d.moon.altitude.toFixed(1) + "°  " + (panel.d.moon.altitude > 0 ? "up" : "down") : ""
                  color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.caption
                }
                Text {
                  text: panel.d ? Math.round(panel.d.moon.distanceKm).toLocaleString(Qt.locale(), "f", 0) + " km" : ""
                  color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.caption
                }
              }
            }
            GridLayout {
              Layout.fillWidth: true
              columns: 2
              columnSpacing: Style.space(6); rowSpacing: Style.space(6)
              Stat { label: "next moonrise"; value: panel.hm(panel.d ? panel.d.moon.nextRise : 0); sub: panel.d ? "in " + panel.until(panel.d.moon.nextRise) : ""; tip: "Upper limb on the horizon, parallax and refraction applied." }
              Stat { label: "next moonset"; value: panel.hm(panel.d ? panel.d.moon.nextSet : 0); sub: panel.d ? "in " + panel.until(panel.d.moon.nextSet) : ""; tip: "Moon upper limb drops below the horizon." }
              Stat { label: "next full moon"; value: panel.d ? panel.until(panel.d.moon.nextFull) : "--"; tint: panel.gold; sub: panel.d ? Qt.formatDateTime(new Date(panel.d.moon.nextFull * 1000), "MMM d HH:mm") : ""; tip: "Meeus ch. 49 true phase, local time: " + (panel.d ? panel.dayDate(panel.d.moon.nextFull) : "") }
              Stat { label: "next new moon"; value: panel.d ? panel.until(panel.d.moon.nextNew) : "--"; tint: panel.blue; sub: panel.d ? Qt.formatDateTime(new Date(panel.d.moon.nextNew * 1000), "MMM d HH:mm") : ""; tip: "Darkest skies for stargazing: " + (panel.d ? panel.dayDate(panel.d.moon.nextNew) : "") }
            }
          }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: panel.faint; border.width: 0 }
        Text {
          Layout.fillWidth: true
          text: "NOAA solar equations + Meeus lunar theory, computed locally, no network.  Location: "
                + (panel.d ? panel.d.locationSource : "--") + ".  Updated " + (panel.d ? panel.hms(panel.d.generated) : "--")
          color: panel.dim; font.family: panel.fontFamily; font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
