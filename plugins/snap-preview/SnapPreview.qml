import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Drag-to-snap destination preview.
//
// Hyprland exposes no event for a window being dragged inside a workspace, so
// this overlay samples the pointer while a *floating* window is active and
// highlights the snap target zone in real time. The sampler lives inside the
// already-running Quickshell process (no separate daemon) and backs off to a
// ~1s cadence whenever nothing is being dragged, so idle cost is negligible.
//
// The overlay surface is a click-through layer-shell panel (empty input
// region), identical in spirit to the OSD plugin: it never intercepts input.
// The real snap itself is Hyprland's native `general:snap`.
Item {
  id: root

  // Mirrors the panel's on/off state so the shell's isPluginOpen works.
  property bool opened: false

  readonly property var monitor: Hyprland.focusedMonitor

  // Reserved area + edge gaps (IPC fetched; refreshed on config change).
  property int resLeft: 0
  property int resTop: 0
  property int resRight: 0
  property int resBottom: 0
  property int gapT: 10
  property int gapR: 10
  property int gapB: 10
  property int gapL: 10
  property int gapIn: 5

  // Distance (in px) from an outer edge/corner that arms the preview.
  property int threshold: 28

  // Active target zone in *global* coordinates, or null while idle.
  property var zone: null

  // Pointer position of the last completed poll (idle-suppression bookkeeping).
  property var pointer: null
  property int samePointerTicks: 0
  property int skipTicks: 0
  property bool envLoaded: false

  function gapTuple(css) {
    var p = String(css || "").trim().split(/\s+/).map(Number)
    if (p.length >= 4) return { t: p[0], r: p[1], b: p[2], l: p[3] }
    if (p.length === 2) return { t: p[0], r: p[1], b: p[0], l: p[1] }
    if (p.length === 1) return { t: p[0], r: p[0], b: p[0], l: p[0] }
    return { t: 10, r: 10, b: 10, l: 10 }
  }

  function refreshEnv() {
    var id = root.monitor && root.monitor.id !== undefined ? root.monitor.id : 0
    envProc.command = [
      "bash", "-c",
      "hyprctl monitors -j -a | jq -c --argjson id '" + id + "' '.[] | select(.id == $id) | .reserved'; " +
      "hyprctl getoption general:gaps_out -j | jq -r .css; " +
      "hyprctl getoption general:gaps_in -j | jq -r .css"
    ]
    envProc.running = true
  }

  function applyEnv(text) {
    var lines = String(text || "").trim().split("\n")
    if (lines.length >= 3) {
      var res = []
      try { res = JSON.parse(lines[0]) } catch (e) {}
      root.resLeft = res[0] || 0
      root.resTop = res[1] || 0
      root.resRight = res[2] || 0
      root.resBottom = res[3] || 0
      var go = root.gapTuple(lines[1])
      root.gapT = go.t
      root.gapR = go.r
      root.gapB = go.b
      root.gapL = go.l
      root.gapIn = root.gapTuple(lines[2]).t
      root.envLoaded = true
    }
  }

  Timer {
    id: sampler
    interval: 45
    repeat: true
    running: true
    onTriggered: root.poll()
  }

  function poll() {
    var tl = Hyprland.activeToplevel
    var ws = tl ? tl.workspace : null
    if (!tl || !ws || ws.id <= 0 || !root.envLoaded) {
      root.setZone(null)
      return
    }
    if (root.skipTicks > 0) {
      root.skipTicks--
      return
    }
    pollProc.command = [
      "bash", "-c",
      "hyprctl activewindow -j | jq -c '{floating, monitor}'; " +
      "hyprctl cursorpos -j | jq -c ."
    ]
    pollProc.running = true
  }

  function onPoll(text) {
    var lines = String(text || "").split("\n")
    var win = null
    var cur = null
    try { win = JSON.parse(lines[0] || "{}") } catch (e) {}
    try { cur = JSON.parse(lines[1] || "{}") } catch (e) {}

    if (!win || win.floating !== true) {
      root.setZone(null)
      return
    }
    if (!cur || cur.x === undefined || cur.y === undefined) {
      root.setZone(null)
      return
    }

    var same = root.pointer && cur.x === root.pointer.x && cur.y === root.pointer.y
    root.pointer = { x: cur.x, y: cur.y }
    if (same) {
      root.samePointerTicks++
    } else {
      root.samePointerTicks = 0
      root.skipTicks = 0
    }
    // Nothing to show and pointer is stationary: back off for a while.
    if (root.zone === null && root.samePointerTicks >= 3) {
      root.skipTicks = 30
      return
    }

    var mon = root.monitor
    if (!mon) {
      root.setZone(null)
      return
    }
    var mx = mon.x || 0
    var my = mon.y || 0
    var mw = mon.width || 0
    var mh = mon.height || 0
    var ax = mx + root.resLeft + root.gapL
    var ay = my + root.resTop + root.gapT
    var aw = mw - root.resLeft - root.resRight - root.gapL - root.gapR
    var ah = mh - root.resTop - root.resBottom - root.gapT - root.gapB
    if (aw <= 0 || ah <= 0) {
      root.setZone(null)
      return
    }
    var hw = Math.floor((aw - root.gapIn) / 2)
    var hh = Math.floor((ah - root.gapIn) / 2)
    var T = root.threshold

    var px = cur.x
    var py = cur.y
    var nearL = px <= ax + T
    var nearR = px >= ax + aw - T
    var nearT = py <= ay + T
    var nearB = py >= ay + ah - T

    var z = null
    if (nearL && nearT) z = { x: ax, y: ay, w: hw, h: hh }
    else if (nearR && nearT) z = { x: ax + hw + root.gapIn, y: ay, w: hw, h: hh }
    else if (nearL && nearB) z = { x: ax, y: ay + hh + root.gapIn, w: hw, h: hh }
    else if (nearR && nearB) z = { x: ax + hw + root.gapIn, y: ay + hh + root.gapIn, w: hw, h: hh }
    else if (nearL) z = { x: ax, y: ay, w: hw, h: ah }
    else if (nearR) z = { x: ax + hw + root.gapIn, y: ay, w: hw, h: ah }
    else if (nearT) z = { x: ax, y: ay, w: aw, h: ah } // full-width top = maximize preview
    root.setZone(z)
  }

  function setZone(z) {
    root.zone = z
    applyZone()
  }

  function applyZone() {
    var mon = root.monitor
    var z = root.zone
    if (!mon || !z) {
      hl.visible = false
      overlay.visible = false
      root.opened = false
      return
    }
    var lx = z.x - (mon.x || 0)
    var ly = z.y - (mon.y || 0)
    var inBounds = lx >= -1 && ly >= -1 && lx + z.w <= overlay.width + 1 && ly + z.h <= overlay.height + 1
    hl.x = lx
    hl.y = ly
    hl.width = z.w
    hl.height = z.h
    hl.visible = inBounds
    overlay.visible = inBounds
    root.opened = inBounds
  }

  Process {
    id: envProc
    stdout: StdioCollector {
      onStreamFinished: root.applyEnv(String(text || ""))
    }
  }

  Process {
    id: pollProc
    stdout: StdioCollector {
      onStreamFinished: root.onPoll(String(text || ""))
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event ? event.name : ""
      if (n === "configreloaded" || n === "monitoradded"
          || n === "monitorremoved" || n === "focusedmon") {
        root.refreshEnv()
      }
    }
  }

  Component.onCompleted: root.refreshEnv()

  PanelWindow {
    id: overlay
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-snap-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Visual-only: keep the input region empty so the preview never blocks
    // the drag or any clicks.
    mask: Region {}

    Rectangle {
      id: hl
      radius: 12
      color: Util.alpha(Color.accent, 0.45)
      border.color: Util.alpha(Color.accent, 0.9)
      border.width: 2
      visible: false
      Behavior on opacity { NumberAnimation { duration: 120 } }
    }
  }
}