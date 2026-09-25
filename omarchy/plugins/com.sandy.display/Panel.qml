import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "com.sandy.display"
  ipcTarget: "com.sandy.display"
  manageIpc: false

  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the brightness + state methods below.
  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property bool brightnessReadQueued: false
  property string internalMonitor: ""
  property string externalMonitor: ""
  property string focusedMonitor: ""
  property bool internalEnabled: false
  property bool mirrorEnabled: false
  property string monitorScale: ""
  property var displays: []
  property int enabledDisplayCount: 0

  // Refresh-rate options for the focused monitor at its current resolution:
  // [{ hz, label, mode }], e.g. [{hz:60,label:"60Hz",...}]. Filled by
  // modesProc (`hyprctl monitors all -j` -> Model.parseRefreshRates), so
  // external outputs show their own rates when focused/clicked.
  property var monitorModes: []
  property double currentRefresh: 0
  // Raw `hyprctl monitors all -j` cache so refresh options recompute when
  // the display list lands (whichever proc finishes first wins).
  property string monitorsJsonCache: ""

  // Explicit configuration target. Set once from compositor focus when
  // the panel opens, then owned ONLY by DISPLAYS clicks afterwards.
  // (Following live focus made the whole panel retarget whenever the
  // mouse crossed monitors — the "settings keep changing" feeling.
  // Focus is still shown per-row via the "· focused" tag.)
  property string selectedMonitor: ""
  property bool selectedManual: false
  // Resolution under edit for the selected monitor ("WxH"); reset to the
  // live mode whenever the target changes. Refresh pills follow it.
  property string selectedResolution: ""
  property var resolutionModes: []

  // Layout / presentation actions for the LAYOUT section (2+ displays).
  readonly property var layoutModes: [
    { key: "extend-right", label: "Extend right" },
    { key: "extend-left", label: "Extend left" },
    { key: "extend-above", label: "Extend above" },
    { key: "extend-below", label: "Extend below" },
    { key: "mirror", label: "Mirror" },
    { key: "internal-only", label: "Internal only" },
    { key: "external-only", label: "External only" }
  ]
  // Live-detected arrangement (extend-right, mirror, ...) so the active
  // button carries a checkmark + accent highlight.
  property string activeLayout: ""

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // Cursor model shared by keyboard and mouse. Sections:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel
  //                  (mirrors Audio's slider rows). Only present if a
  //                  controllable backlight was detected.
  //   "scale"      - 6 Button scale presets; treated as a single
  //                  horizontal row from j/k's perspective. h/l moves
  //                  between presets, identical to bluetooth's header.
  //   "monitors"   - vertical display row list for enabling/disabling displays;
  //                  j/k walks each row.
  //   "refresh"    - refresh-rate pills for the focused monitor; single
  //                  horizontal row like "scale" (only when 2+ rates exist).
  //   "layout"     - arrangement/presentation buttons; single horizontal
  //                  row (only when 2+ displays are connected).
  // Mouse hover on a target updates root state via the components' `hovered`
  // signal so keyboard cursor and pointer share one highlight.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  // Dimensions of the selected target (SCALE presets + headers follow the
  // click, not compositor focus).
  function selectedDisplay() {
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.name === selectedMonitor) return display
    }
    return null
  }
  // The single output every value control (SCALE / RESOLUTION / REFRESH /
  // BRIGHTNESS) acts on: the monitor explicitly clicked in DISPLAYS, falling
  // back to the compositor-focused one only when no explicit selection exists.
  // Following live focus once a monitor is picked is what made clicks on
  // HDMI-A-1 edit eDP-1, so ownership is one-way: click wins, forever.
  function activeTargetMonitor() {
    if (selectedMonitor !== "") return selectedMonitor
    if (focusedMonitor !== "") return focusedMonitor
    return ""
  }
  readonly property var scaleValues: {
    var sel = selectedDisplay()
    if (sel) return Model.availableScales(scalePresets, sel.width, sel.height)
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.availableScales(scalePresets, display.width, display.height)
    }
    return scalePresets
  }
  property string focusSection: "scale"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Text size slider — curated macOS-style notches (px). With a single
  // display it edits the ONE global base-size (shell bar fonts + bar height,
  // GTK text-scaling, terminals). With 2+ displays the slider re-scopes to
  // the SELECTED monitor's EFFECTIVE text size (= global base × that monitor's
  // Hyprland scale): dragging it retargets that output's scale so only that
  // screen's UI (bar + panels + GTK + terminals) resizes. The "BASE" pill in
  // the header flips the slider back to the shared global base-size knob.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // Scope of the TEXT SIZE slider: "target" (selected monitor's effective
  // size via its scale) or "global" (the shared base-size). Stays "target";
  // with a single display the effective size IS the base, so it degrades to
  // the global slider automatically.
  property string textScope: "target"
  readonly property bool targetTextScope: textScope === "target" && root.enabledDisplayCount > 1
  // While a change is in flight, the chosen stop index overrides the live
  // value so the knob doesn't snap back during the file/scale round-trip.
  // -1 = no pending change; follow the live (effective/global) value.
  property int textSizePreviewIndex: -1

  // A text-size change reflows the whole panel (both font and spacing scale),
  // which slides rows under a stationary pointer and fires synthetic hover.
  // While true, hover is not allowed to hijack the keyboard focus section —
  // otherwise h/l on the text-size slider can jump focus to another row.
  property bool reflowingText: false
  function markReflowing() {
    root.reflowingText = true
    reflowSettle.restart()
  }

  readonly property var visibleSections: {
    var list = []
    if (brightnessAvailable) list.push("brightness")
    list.push("textsize")
    list.push("scale")
    // RESOLUTION and REFRESH RATE are always navigable once a target
    // exists — even with a single option (e.g. one resolution on eDP-1,
    // one rate on HDMI-A-1@1080p). Hiding them there made each monitor
    // look like it lacked the other control.
    if (selectedMonitor !== "") list.push("resolution")
    if (selectedMonitor !== "") list.push("refresh")
    if (displays.length > 1) list.push("monitors")
    if (displays.length > 1) list.push("layout")
    return list
  }

  function sectionCount(section) {
    if (section === "brightness") return 0  // only the slider sentinel at -1
    if (section === "textsize") return 0    // slider sentinel at -1, like brightness
    if (section === "scale") return scaleValues.length
    if (section === "resolution") return resolutionModes.length
    if (section === "refresh") return monitorModes.length
    if (section === "monitors") return displays.length
    if (section === "layout") return layoutModes.length
    return 0
  }

  function sectionIsSingleRow(section) {
    // brightness and text size are lone sliders; scale/resolution/refresh
    // presets and layout buttons sit horizontally.
    return section === "brightness" || section === "textsize"
      || section === "scale" || section === "resolution"
      || section === "refresh" || section === "layout"
  }

  function sectionFirstIndex(section) {
    if (section === "brightness" || section === "textsize") return -1
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections || sections.length === 0) return
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var inSingleRow = sectionIsSingleRow(focusSection)
    var max = inSingleRow ? 0 : sectionCount(focusSection) - 1

    if (delta > 0) {
      if (!inSingleRow && selectedIndex < max) { selectedIndex = selectedIndex + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      if (!inSingleRow && selectedIndex > 0) { selectedIndex = selectedIndex - 1; return }
      if (sIdx > 0) {
        var prev = sections[sIdx - 1]
        focusSection = prev
        // Coming up from below — land on the last navigable row of the prev
        // section, or its sentinel for single-row sections.
        selectedIndex = sectionIsSingleRow(prev) ? sectionFirstIndex(prev) : sectionCount(prev) - 1
      }
    }
  }

  // h/l: in scale/resolution/refresh/layout sections, walks the horizontal row;
  // everywhere else, no-op because adjustBrightness handles horizontal
  // motion on the brightness slider.
  function moveCursorH(delta) {
    if (focusSection !== "scale" && focusSection !== "resolution"
        && focusSection !== "refresh" && focusSection !== "layout") return
    var count = sectionCount(focusSection)
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > count - 1) next = count - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness") return
    if (!brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
      setScale(scaleValues[selectedIndex])
      return
    }
    if (focusSection === "resolution" && selectedIndex >= 0 && selectedIndex < resolutionModes.length) {
      setResolution(resolutionModes[selectedIndex].res)
      return
    }
    if (focusSection === "refresh" && selectedIndex >= 0 && selectedIndex < monitorModes.length) {
      setRefreshRate(monitorModes[selectedIndex].hz)
      return
    }
    if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < displays.length) {
      var d = displays[selectedIndex]
      if (d) selectMonitor(d.name)
      return
    }
    if (focusSection === "layout" && selectedIndex >= 0 && selectedIndex < layoutModes.length) {
      setLayout(layoutModes[selectedIndex].key)
      return
    }
    // brightness: no separate action; the slider value is the action.
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    var count = sectionCount(focusSection)
    if (sectionIsSingleRow(focusSection)) {
      // brightness/text size use the -1 sentinel; scale clamps into the presets.
      if (focusSection === "brightness" || focusSection === "textsize") selectedIndex = -1
      else if (selectedIndex < 0 || selectedIndex >= count) selectedIndex = 0
      return
    }
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel grows
  // taller than its allotted height (lots of displays). Mirrors audio's
  // ensureCursorVisible helper.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function brightnessIpc(percent) {
    var value = Number(percent)
    root.setBrightness(value)
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      focusedMonitor: root.focusedMonitor,
      selectedMonitor: root.selectedMonitor,
      selectedResolution: root.selectedResolution,
      scale: root.monitorScale,
      refresh: root.currentRefresh,
      refreshModes: root.monitorModes,
      resolutionModes: root.resolutionModes,
      activeLayout: root.activeLayout,
      gpuMode: root.gpuMode,
      displays: root.displays
    })
  }

  IpcHandler {
    target: "com.sandy.display"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
    function select(monitor: string): string { root.selectMonitor(monitor); return root.selectedMonitor }
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!modesProc.running) modesProc.running = true
    if (!gpuProc.running) gpuProc.running = true
  }

  function setBrightness(value) {
    var percent = Model.clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    var target = root.activeTargetMonitor()
    if (!target) return
    root.brightnessSetQueued = false
    // Per-target, never focused: internal outputs adjust the backlight
    // (brightnessctl), external outputs go through DDC/CI (ddcutil), so the
    // clicked monitor's brightness changes and nothing else's.
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", target, percent + "%"]
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = Model.clampBrightness(value)
    brightnessDebounce.restart()
  }

  // (Re)read brightness for the CURRENT configuration target (selected, else
  // focused). Runs on open, on selection change, and on each state poll.
  // Brightness availability is per-target too: selecting a monitor without a
  // controllable backlight/DDC bus hides the section ("FIXED BRIGHTNESS").
  function refreshBrightness() {
    var target = root.activeTargetMonitor()
    if (!target) return
    if (brightnessReadProc.running) { root.brightnessReadQueued = true; return }
    brightnessReadProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", target]
    brightnessReadProc.running = true
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: "brightness",
      value: percent
    }))
  }

  function normalizeScale(scale) {
    return Model.normalizeScale(scale)
  }

  function activeScaleIndex() {
    var sel = selectedDisplay()
    if (sel) return Model.matchingScaleIndex(scaleValues, monitorScale, sel.width, sel.height)
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.matchingScaleIndex(scaleValues, monitorScale, display.width, display.height)
    }
    return -1
  }

  function effectiveScale(scale) {
    var sel = selectedDisplay()
    if (sel) return Model.cleanScale(scale, sel.width, sel.height)
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display && display.focused)
        return Model.cleanScale(scale, display.width, display.height)
    }
    return normalizeScale(scale)
  }

  // Playful mood-name for a given brightness percent. Bands intentionally
  // span ~10–20 points so casual tweaks change the label, while small
  // nudges within one band don't.
  function brightnessName(percent) {
    return Model.brightnessName(percent)
  }

  function updateDisplays(displaysJson) {
    var parsed = Model.parseDisplays(displaysJson)
    root.displays = parsed.displays
    root.enabledDisplayCount = parsed.enabledDisplayCount
  }

  function toggleDisplay(name, enabled) {
    if (!name) return
    if (enabled && root.enabledDisplayCount <= 1) return

    actionProc.command = ["hyprctl", "keyword", "monitor", name + (enabled ? ",disable" : ",preferred,auto,auto")]
    if (!actionProc.running) actionProc.running = true
  }

  function setScale(scale) {
    var target = root.activeTargetMonitor()
    if (!target) return
    // ALWAYS the explicitly selected output. Never the omarchy-hyprland-monitor-
    // scaling shortcut: that helper targets the compositor's FOCUSED monitor
    // (`select(.focused == true)`) and rewrites monitors.lua's generic output=""
    // catch-all, which lets one click retarget every monitor. Scoping must stay
    // exact, so the per-output omarchy-display-mode path is used unconditionally.
    actionProc.command = ["omarchy-display-mode", "scale", target, String(scale)]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- Explicit target: DISPLAYS rows select, they don't toggle ----
  function selectMonitor(name) {
    if (!name) return
    selectedManual = true
    selectedMonitor = name
    // Reset the resolution under edit to the target's live mode; refresh
    // pills recompute for it below.
    var sel = selectedDisplay()
    if (sel && sel.width > 0 && sel.height > 0)
      selectedResolution = sel.width + "x" + sel.height
    if (monitorsJsonCache !== "") updateModes(monitorsJsonCache)
    clampCursor()
  }

  // ---- Resolution (per selected monitor, via omarchy-display-mode) ----
  function activeResolutionIndex() {
    for (var i = 0; i < resolutionModes.length; i++)
      if (resolutionModes[i].res === selectedResolution) return i
    return -1
  }

  function setResolution(res) {
    var target = root.activeTargetMonitor()
    if (!target || !res) return
    selectedResolution = res
    actionProc.command = ["omarchy-display-mode", "resolution", target, res]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- Refresh rate (per selected monitor+resolution) ----
  function activeRefreshIndex() {
    return Model.matchingRefreshIndex(monitorModes, currentRefresh)
  }

  function setRefreshRate(hz) {
    var target = root.activeTargetMonitor()
    if (!target) return
    actionProc.command = ["omarchy-display-mode", "refresh", target, String(hz)]
    if (!actionProc.running) actionProc.running = true
  }

  function updateModes(monitorsJson) {
    if (!selectedMonitor) return
    var selW = 0, selH = 0, rr = 0
    var liveW = 0, liveH = 0
    var sel = selectedDisplay()
    if (sel) { selW = sel.width; selH = sel.height }
    // Default the resolution under edit to the target's live mode.
    if (!selectedResolution && selW > 0 && selH > 0)
      selectedResolution = selW + "x" + selH
    var rw = selW, rh = selH
    if (selectedResolution) {
      var parts = String(selectedResolution).split("x")
      if (parts.length === 2 && Number(parts[0]) > 0 && Number(parts[1]) > 0) {
        rw = Number(parts[0]); rh = Number(parts[1])
      }
    }
    var mons = []
    try {
      mons = JSON.parse(String(monitorsJson || "[]"))
    } catch (e) {
      mons = []
    }
    if (Array.isArray(mons)) {
      for (var k = 0; k < mons.length; k++) {
        if (mons[k] && mons[k].name === selectedMonitor) {
          rr = Number(mons[k].refreshRate) || 0
          liveW = Number(mons[k].width) || 0
          liveH = Number(mons[k].height) || 0
          break
        }
      }
    }
    root.currentRefresh = rr
    root.activeLayout = Model.detectLayout(monitorsJson)
    root.resolutionModes = Model.parseResolutions(monitorsJson, selectedMonitor)
    // Adopt externally applied resolutions (other tools, lid events) so the
    // pills never describe a stale mode; a just-clicked pill already equals
    // live, so this never fights the user.
    if (liveW > 0 && liveH > 0) {
      var liveRes = liveW + "x" + liveH
      if (liveRes !== selectedResolution) {
        for (var r = 0; r < root.resolutionModes.length; r++) {
          if (root.resolutionModes[r].res === liveRes) {
            selectedResolution = liveRes
            var lp = liveRes.split("x")
            rw = Number(lp[0]); rh = Number(lp[1])
            break
          }
        }
      }
    }
    root.monitorModes = Model.parseRefreshRates(monitorsJson, selectedMonitor, rw, rh)
    // Per-SELECTED-monitor scale, straight from the live dump. Both the TEXT
    // SIZE effective-size math and the SCALE-preset highlight depend on it, so
    // it must never describe the focused output once a target is chosen.
    var targetScale = Model.scaleFor(String(monitorsJson || ""), selectedMonitor)
    if (targetScale !== "") root.monitorScale = targetScale
    // Drop the pending TEXT SIZE preview once the applied scale settles on the
    // chosen stop, so the knob tracks the live effective size again.
    if (root.textSizePreviewIndex >= 0) {
      var targetEffective = Math.round(Style.font.baseSize * root.targetTextScale())
      if (root.nearestTextStop(targetEffective) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  // ---- Layout / presentation (2+ displays, via omarchy-display-mode) ----
  function setLayout(mode) {
    actionProc.command = ["omarchy-display-mode", "layout", mode]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- Text size (global base via one CLI, OR per-selected-monitor scale) ----
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) { bestDist = d; best = i }
    }
    return best
  }

  // The selected monitor's live scale as a number (1 when unknown).
  function targetTextScale() {
    var s = parseFloat(String(root.monitorScale || ""))
    return isFinite(s) && s > 0 ? s : 1
  }

  // True effective text size on the selected monitor = global base × scale.
  function effectiveTargetTextPx() {
    return Math.round(Style.font.baseSize * root.targetTextScale())
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise where the live value (per-monitor effective or global base)
  // rounds to.
  function currentTextIndex() {
    if (textSizePreviewIndex >= 0) return textSizePreviewIndex
    var px = root.targetTextScope ? root.effectiveTargetTextPx() : Style.font.baseSize
    return root.nearestTextStop(px)
  }

  // px shown in the header: the pending stop if any, else the true value
  // (off-notch effective/global sizes that come from the CLI or scale).
  function displayedTextPx() {
    return textSizePreviewIndex >= 0
      ? textSizeStops[textSizePreviewIndex]
      : (root.targetTextScope ? root.effectiveTargetTextPx() : Style.font.baseSize)
  }

  // Shared path for slider drags and h/l keys: take a stop, preview it, then
  // apply it to whichever scope the slider currently owns. A stop that already
  // equals the selected monitor's live effective size is a no-op, so clicking
  // the current position never rewrites an off-preset scale.
  function setTextSizeFromStop(idx) {
    var px = textSizeStops[idx]
    if (root.targetTextScope && Math.round(root.effectiveTargetTextPx()) === px) return
    markReflowing()
    textSizePreviewIndex = idx
    if (root.targetTextScope) root.setTargetTextSize(px)
    else root.setTextSize(px)
  }

  // The global base-size knob: shell bar fonts + bar height, GTK text-scaling,
  // terminal point size — one number the whole desktop shares. Editing it here
  // rescales every monitor proportionally (bar + GTK + terminals).
  function setTextSize(px) {
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    if (!textScaleProc.running) textScaleProc.running = true
  }

  // Per-monitor effective text size: pick the achievable scale for the SELECTED
  // output whose cleaned value lands closest to desiredPx/globalBase, then
  // apply it through the same explicit-output path as the SCALE pills. Only
  // that monitor's UI grows or shrinks.
  function setTargetTextSize(px) {
    var base = Style.font.baseSize
    if (!isFinite(base) || base <= 0) return
    if (Math.round(root.effectiveTargetTextPx()) === px) return
    var target = root.activeTargetMonitor()
    if (!target) return
    var desired = Number(px) / base
    var sel = root.selectedDisplay()
    var w = sel ? sel.width : 0
    var h = sel ? sel.height : 0
    var bestScale = null
    var bestDist = Infinity
    for (var i = 0; i < root.scaleValues.length; i++) {
      var clean = parseFloat(Model.cleanScale(root.scaleValues[i], w, h))
      if (!isFinite(clean) || clean <= 0) continue
      var d = Math.abs(clean - desired)
      if (d < bestDist) { bestDist = d; bestScale = root.scaleValues[i] }
    }
    if (bestScale === null) return
    root.setScale(bestScale)
  }

  function adjustTextSize(deltaSteps) {
    var idx = root.currentTextIndex() + deltaSteps
    if (idx < 0) idx = 0
    if (idx > textSizeStops.length - 1) idx = textSizeStops.length - 1
    root.setTextSizeFromStop(idx)
  }

  function toggleTextScope() {
    if (root.enabledDisplayCount <= 1) return
    textSizePreviewIndex = -1
    root.textScope = root.textScope === "target" ? "global" : "target"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // KeyboardPanel primes focus at open-time, so SUPER-bound IPC summons land
  // with j/k ready to navigate. Keep a default landing point, but don't paint
  // the cursor until hover or the first navigation key.
  onOpenedChanged: {
    if (opened) {
      // Fresh target every open: snapshot compositor focus once. Further
      // focus changes (mouse crossing monitors) must NOT retarget.
      selectedManual = false
      selectedResolution = ""
      selectedMonitor = ""
      if (focusedMonitor !== "") {
        selectedMonitor = focusedMonitor
        var sel = selectedDisplay()
        if (sel && sel.width > 0 && sel.height > 0)
          selectedResolution = sel.width + "x" + sel.height
      }
      refresh()
      if (brightnessAvailable) {
        focusSection = "brightness"
        selectedIndex = -1
      } else {
        focusSection = "scale"
        selectedIndex = 0
      }
      cursorActive = false
    }
  }

  onFocusedMonitorChanged: {
    // One-time adoption only: fill an empty target (first data after open).
    // Never override afterwards — neither an explicit click nor the
    // open-time snapshot may be stolen by mouse-focus movement.
    if (selectedMonitor === "" && focusedMonitor !== "") {
      selectedMonitor = focusedMonitor
      var sel = selectedDisplay()
      selectedResolution = (sel && sel.width > 0 && sel.height > 0)
        ? sel.width + "x" + sel.height : ""
      if (opened && monitorsJsonCache !== "") updateModes(monitorsJsonCache)
      root.refreshBrightness()
    }
  }

  onBrightnessAvailableChanged: clampCursor()
  onDisplaysChanged: {
    clampCursor()
    if (monitorsJsonCache !== "") updateModes(monitorsJsonCache)
  }
  onMonitorModesChanged: clampCursor()
  onResolutionModesChanged: clampCursor()
  onSelectedMonitorChanged: {
    clampCursor()
    // Re-point brightness at the newly selected output (backlight vs DDC).
    root.refreshBrightness()
  }
  onScaleValuesChanged: clampCursor()
  onVisibleSectionsChanged: clampCursor()

  // Only poll while the panel is open; the bar glyph tracks monitor count via
  // Quickshell.screens, and open-time refresh + Component.onCompleted cover the
  // rest. External brightness changes are reflected whenever the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        // lines[0] is the FOCUSED monitor's brightness and is deliberately
        // ignored — brightness is read fresh for the explicitly selected
        // target below, so it can never chase the mouse across monitors.
        root.refreshBrightness()
        root.internalMonitor = String(lines[1] || "").trim()
        root.externalMonitor = String(lines[2] || "").trim()
        root.internalEnabled = String(lines[3] || "").trim() !== ""
        root.mirrorEnabled = String(lines[4] || "").trim() === root.externalMonitor && root.externalMonitor !== ""
        root.focusedMonitor = String(lines[5] || "").trim()
        // Scale is owned by the SELECTED target via updateModes (modesProc
        // carries the per-monitor value); this focused-monitor line is only a
        // stopgap before the first explicit selection lands. It must never
        // overwrite the selected monitor's scale — else TEXT SIZE and the
        // SCALE highlight would chase the mouse across outputs.
        if (root.selectedMonitor === "")
          root.monitorScale = root.normalizeScale(String(lines[6] || "").trim())
        root.updateDisplays(String(lines[7] || "[]").trim())
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Do NOT call refresh() after a brightness set completes. The local
    // brightnessPercent we just wrote is authoritative; re-reading via
    // `omarchy-brightness-display` races the hardware/driver and can
    // return an empty string, which the parser then coerces to 0 —
    // visible as a "bounce to zero" after h/l keypresses. External
    // brightness changes are still picked up by the 5s periodic refresh,
    // the open-time refresh, and Component.onCompleted.
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) {
        root.setBrightness(root.pendingBrightnessPercent)
      }
    }
  }

  // Reads brightness for the SELECTED target output (backlight for
  // eDP/LVDS/DSI, DDC/CI for external), never the focused one. Availability
  // is per-target: no device behind the output hides the section.
  Process {
    id: brightnessReadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        var available = raw !== "" && raw !== "unavailable"
        root.brightnessAvailable = available
        root.brightnessPercent = available ? Model.clampBrightness(raw) : 0
      }
    }
    onRunningChanged: {
      if (running) return
      if (root.brightnessReadQueued) {
        root.brightnessReadQueued = false
        root.refreshBrightness()
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  // ---- GPU mode (supergfxctl/envycontrol via omarchy-display-mode) ----
  // Raw backend word: integrated | hybrid | nvidia | dedicated | unknown.
  property string gpuMode: "unknown"
  readonly property var gpuModes: [
    { key: "igpu", label: "iGPU" },
    { key: "hybrid", label: "Hybrid" },
    { key: "dgpu", label: "dGPU" }
  ]

  function gpuKeyFor(mode) {
    var m = String(mode || "").toLowerCase()
    if (m === "integrated" || m === "igpu") return "igpu"
    if (m === "hybrid") return "hybrid"
    if (m === "nvidia" || m === "dedicated" || m === "dgpu") return "dgpu"
    return ""
  }

  function setGpuMode(key) {
    if (key !== "igpu" && key !== "hybrid" && key !== "dgpu") return
    // Optimistic highlight; refresh() after the action re-reads the truth.
    gpuMode = key === "igpu" ? "integrated" : key === "dgpu" ? "nvidia" : "hybrid"
    actionProc.command = ["omarchy-display-mode", "gpu-set", key]
    if (!actionProc.running) actionProc.running = true
  }

  // Full `hyprctl monitors all -j` dump: feeds refresh-rate options and the
  // live rate for the focused monitor. actionProc refreshes afterwards so
  // pills highlight the newly applied mode.
  Process {
    id: modesProc
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.monitorsJsonCache = String(text || "")
        root.updateModes(root.monitorsJsonCache)
      }
    }
  }

  // Non-blocking GPU mode query; never fails the panel when no backend
  // (supergfxctl/envycontrol) is installed — gpuMode stays "unknown".
  // Absolute path: bare-name lookup proved flaky for this proc under the
  // shell's environment even though sibling procs resolve fine.
  Process {
    id: gpuProc
    command: ["/home/sandy/.local/bin/omarchy-display-mode", "gpu"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = String(text || "").trim().toLowerCase()
        root.gpuMode = m !== "" ? m : "unknown"
      }
    }
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  Process {
    id: textScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Clears the hover-suppression flag once the reflow triggered by a text-size
  // change has settled.
  Timer {
    id: reflowSettle
    interval: 300
    repeat: false
    onTriggered: root.reflowingText = false
  }

  // Once the live value (per-monitor effective size or global base, whichever
  // scope the slider owns) catches up to the pending choice, drop the preview
  // so the slider tracks the real value again. The change itself reflows the
  // panel for the global path, so suppress hover for a beat while it lands.
  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      root.markReflowing()
      if (root.textSizePreviewIndex < 0) return
      var px = root.targetTextScope
        ? root.effectiveTargetTextPx()
        : Style.font.baseSize
      if (root.nearestTextStop(px) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "textsize") root.adjustTextSize(dx)
          else if (root.focusSection === "scale" || root.focusSection === "resolution"
                   || root.focusSection === "refresh"
                   || root.focusSection === "layout") root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: display icon · title/status · GPU mode ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, gpuBox.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.displays.length > 1 ? "󰍺" : "󰍹"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            // Compact GPU mode switcher in the header's right-side empty
            // space: [ iGPU | Hybrid | dGPU ], active pill accented.
            Item {
              id: gpuBox
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: gpuRow.implicitWidth
              implicitHeight: gpuRow.implicitHeight

              Row {
                id: gpuRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs
                // Dim the whole switcher until a backend (supergfxctl /
                // envycontrol) reports a real mode — an unhighlighted row
                // must read as "unknown", not as a style choice.
                opacity: root.gpuKeyFor(root.gpuMode) !== "" ? 1.0 : 0.45

                Repeater {
                  model: root.gpuModes

                  GpuPill {
                    required property var modelData
                    required property int index

                    gpuKey: modelData.key
                    gpuLabel: modelData.label
                  }
                }
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: gpuBox.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Display"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                textFormat: Text.PlainText
                text: {
                  if (root.brightnessAvailable) {
                    return root.brightnessName(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent).toUpperCase()
                  }
                  return "FIXED BRIGHTNESS"
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Brightness ----------
          PanelSeparator {
            visible: root.brightnessAvailable
            foreground: root.bar.foreground
          }

          Column {
            visible: root.brightnessAvailable
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

              PanelSectionHeader {
                id: brightnessHeader
                text: "BRIGHTNESS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the output BRIGHTNESS targets — reads via backlight
              // (internal) or DDC/CI (external) exactly as the click chose.
              Text {
                id: brightnessMonitor
                textFormat: Text.PlainText
                text: root.activeTargetMonitor()
                visible: root.enabledDisplayCount > 1 && root.activeTargetMonitor() !== ""
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.left: brightnessHeader.right
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: brightnessPercent
                textFormat: Text.PlainText
                text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: brightnessRow
              width: parent.width
              height: brightnessSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "brightness" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(brightnessRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: brightnessSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 1
                maximum: 100
                step: 1
                value: root.brightnessPercent
                integer: true
                onMoved: function(v) { root.previewBrightness(v) }
                onReleased: function(v) {
                  brightnessDebounce.stop()
                  root.setBrightness(v)
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "brightness"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Text size ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight, basePill.implicitHeight)

              PanelSectionHeader {
                id: textSizeHeader
                text: "TEXT SIZE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the monitor whose EFFECTIVE text size the slider owns when
              // it is per-monitor scoped (2+ displays), mirroring the other
              // target-labelled sections.
              Text {
                id: textSizeMonitor
                textFormat: Text.PlainText
                text: root.activeTargetMonitor()
                visible: root.enabledDisplayCount > 1 && root.activeTargetMonitor() !== ""
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.left: textSizeHeader.right
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
              }

              // The shared global base-size the whole desktop uses. Active
              // while the slider is GLOBAL-scoped; clicking flips the slider
              // between "this monitor's effective size" and "global base size".
              Button {
                id: basePill
                text: "BASE " + Style.font.baseSize + "px"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.xxs
                bordered: true
                active: root.textScope === "global"
                visible: root.enabledDisplayCount > 1
                anchors.right: textSizePx.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.toggleTextScope()
              }

              Text {
                id: textSizePx
                textFormat: Text.PlainText
                text: (textSizeSlider.dragging
                       ? root.textSizeStops[Math.round(textSizeSlider.liveValue)]
                       : root.displayedTextPx()) + "px"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            CursorSurface {
              id: textSizeRow
              width: parent.width
              height: textSizeSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "textsize" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(textSizeRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: textSizeSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: root.textSizeStops.length - 1
                step: 1
                integer: true
                tickCount: root.textSizeStops.length
                value: root.currentTextIndex()
                onReleased: function(v) { root.setTextSizeFromStop(Math.round(v)) }
              }

              HoverHandler {
                onHoveredChanged: if (hovered && !root.reflowingText) {
                  root.cursorActive = true
                  root.focusSection = "textsize"
                  root.selectedIndex = -1
                }
              }
            }
          }

          // ---------- Scale ----------
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(scaleHeader.implicitHeight, scaleMonitor.implicitHeight)

              PanelSectionHeader {
                id: scaleHeader
                text: "SCALE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the monitor SCALE targets: the selected one, since it
              // only applies there.
              Text {
                id: scaleMonitor
                textFormat: Text.PlainText
                text: root.selectedMonitor !== "" ? root.selectedMonitor : root.focusedMonitor
                // Only worth naming when more than one display is in play.
                visible: (root.selectedMonitor !== "" || root.focusedMonitor !== "") && root.enabledDisplayCount > 1
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Grid {
              id: scaleRow
              width: parent.width
              columns: root.scaleValues.length
              spacing: Style.spacing.xs

              readonly property real cellWidth: root.scaleValues.length > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.scaleValues

                ScalePill {
                  required property string modelData
                  required property int index

                  scaleValue: modelData
                  scaleIndex: index
                  width: scaleRow.cellWidth
                }
              }
            }
          }

          // ---------- Resolution ----------
          PanelSeparator {
            visible: root.selectedMonitor !== ""
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.selectedMonitor !== ""

            Item {
              width: parent.width
              implicitHeight: Math.max(resolutionHeader.implicitHeight, resolutionMonitor.implicitHeight)

              PanelSectionHeader {
                id: resolutionHeader
                text: "RESOLUTION"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: resolutionMonitor
                textFormat: Text.PlainText
                text: root.selectedMonitor !== "" ? root.selectedMonitor : root.focusedMonitor
                visible: (root.selectedMonitor !== "" || root.focusedMonitor !== "") && root.enabledDisplayCount > 1
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // Two-up wrapping grid: labels are wide ("1920x1080 (16:9)").
            Grid {
              id: resolutionRow
              width: parent.width
              columns: 2
              spacing: Style.spacing.xs

              readonly property real cellWidth: (width - spacing) / 2

              Repeater {
                model: root.resolutionModes

                ResolutionPill {
                  required property var modelData
                  required property int index

                  resValue: modelData.res
                  resLabel: modelData.label
                  resIndex: index
                  width: resolutionRow.cellWidth
                }
              }
            }
          }

          // ---------- Refresh rate ----------
          PanelSeparator {
            visible: root.selectedMonitor !== ""
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.selectedMonitor !== ""

            Item {
              width: parent.width
              implicitHeight: Math.max(refreshHeader.implicitHeight, refreshMonitor.implicitHeight)

              PanelSectionHeader {
                id: refreshHeader
                text: "REFRESH RATE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              // Name the monitor the rate targets, like SCALE does.
              Text {
                id: refreshMonitor
                textFormat: Text.PlainText
                text: root.selectedMonitor !== "" ? root.selectedMonitor : root.focusedMonitor
                visible: (root.selectedMonitor !== "" || root.focusedMonitor !== "") && root.enabledDisplayCount > 1
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            // Wrapping grid (4-up): high-refresh panels can expose 4+
            // steps (60/75/120/144/165/240Hz) and must not overflow.
            Grid {
              id: refreshRow
              width: parent.width
              columns: Math.min(4, root.monitorModes.length)
              spacing: Style.spacing.xs

              readonly property real cellWidth: columns > 0
                ? (width - spacing * (columns - 1)) / columns
                : 0

              Repeater {
                model: root.monitorModes

                RefreshPill {
                  required property var modelData
                  required property int index

                  rateHz: modelData.hz
                  rateLabel: modelData.label
                  rateIndex: index
                  width: refreshRow.cellWidth
                }
              }
            }
          }

          // ---------- Monitors ----------
          PanelSeparator {
            visible: root.displays.length > 1
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.displays.length > 1

            PanelSectionHeader {
              text: "DISPLAYS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.displays

              MonitorRow {
                required property var modelData
                required property int index

                width: panelColumn.width
                display: modelData
                rowIndex: index
              }
            }
          }

          // ---------- Layout / presentation ----------
          PanelSeparator {
            visible: root.displays.length > 1
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.displays.length > 1

            PanelSectionHeader {
              text: "LAYOUT"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Grid {
              id: layoutRow
              width: parent.width
              columns: 2
              spacing: Style.spacing.xs

              readonly property real cellWidth: (width - spacing) / 2

              Repeater {
                model: root.layoutModes

                LayoutPill {
                  required property var modelData
                  required property int index

                  layoutKey: modelData.key
                  layoutLabel: modelData.label
                  layoutIndex: index
                  width: layoutRow.cellWidth
                }
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  component ScalePill: Button {
    id: pill
    required property string scaleValue
    required property int scaleIndex

    text: root.effectiveScale(scaleValue) + "x"
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.activeScaleIndex() === scaleIndex
    hasCursor: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === scaleIndex

    onClicked: root.setScale(scaleValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "scale"
      root.selectedIndex = pill.scaleIndex
    }
  }

  component RefreshPill: Button {
    id: refreshPill
    required property int rateHz
    required property string rateLabel
    required property int rateIndex

    text: rateLabel
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.activeRefreshIndex() === rateIndex
    hasCursor: root.cursorActive && root.focusSection === "refresh" && root.selectedIndex === rateIndex

    onClicked: root.setRefreshRate(rateHz)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "refresh"
      root.selectedIndex = refreshPill.rateIndex
    }
  }

  // Compact header pill for the GPU mode switcher ([ iGPU | Hybrid | dGPU ]).
  // Tighter than section pills so three fit beside the hero title.
  component GpuPill: Button {
    id: gpuPill
    required property string gpuKey
    required property string gpuLabel

    readonly property bool isActive: root.gpuKeyFor(root.gpuMode) === gpuKey

    text: gpuLabel + (isActive ? " ✓" : "")
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.xs
    verticalPadding: Style.spacing.xs
    bordered: true

    active: isActive

    onClicked: root.setGpuMode(gpuKey)
  }

  component ResolutionPill: Button {    id: resolutionPill
    required property string resValue
    required property string resLabel
    required property int resIndex

    text: resLabel
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.activeResolutionIndex() === resIndex
    hasCursor: root.cursorActive && root.focusSection === "resolution" && root.selectedIndex === resIndex

    onClicked: root.setResolution(resValue)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "resolution"
      root.selectedIndex = resolutionPill.resIndex
    }
  }
  component LayoutPill: Button {
    id: layoutPill
    required property string layoutKey
    required property string layoutLabel
    required property int layoutIndex

    readonly property bool isActive: root.activeLayout !== "" && root.activeLayout === layoutKey

    text: layoutLabel + (isActive ? " ✓" : "")
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: isActive
    hasCursor: root.cursorActive && root.focusSection === "layout" && root.selectedIndex === layoutIndex

    onClicked: root.setLayout(layoutKey)
    onHovered: function(isHovered) {
      if (!isHovered || root.reflowingText) return
      root.cursorActive = true
      root.focusSection = "layout"
      root.selectedIndex = layoutPill.layoutIndex
    }
  }
  component MonitorRow: CursorSurface {
    id: monitorRow
    required property var display
    required property int rowIndex

    readonly property bool isFocused: display && display.focused
    readonly property bool isSelected: display && display.name === root.selectedMonitor
    readonly property bool canToggle: display && (!display.enabled || root.enabledDisplayCount > 1)

    hasCursor: root.cursorActive && root.focusSection === "monitors" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(monitorRow)
    // Selected target shares the active fill so the row being configured
    // is unmistakable; the label names the state explicitly.
    current: isFocused || isSelected
    foreground: root.bar.foreground
    fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)
    implicitHeight: monitorInner.implicitHeight + Style.spacing.xl
    opacity: canToggle ? 1.0 : 0.45

    Row {
      id: monitorInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "󰍹"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.name
          + (monitorRow.display.focused ? " · focused" : "")
          + (monitorRow.isSelected ? " · selected" : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: monitorRow.isSelected
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(22) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }

      // Enable/disable glyph (the click zone is handled by the row's
      // single MouseArea below, which routes right-edge clicks here —
      // a nested MouseArea would lose to the row-level one in stacking).
      Text {
        textFormat: Text.PlainText
        text: monitorRow.display.enabled ? "󰄬" : "○"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        width: Style.space(22)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
        root.cursorActive = true
        root.focusSection = "monitors"
        root.selectedIndex = monitorRow.rowIndex
      }
      // Right-edge clicks (on the power glyph) toggle the output;
      // anywhere else selects it as the configuration target.
      onClicked: function(mouse) {
        if (mouse.x > width - Style.space(28) && monitorRow.canToggle)
          root.toggleDisplay(monitorRow.display.name, monitorRow.display.enabled)
        else
          root.selectMonitor(monitorRow.display.name)
      }
    }
  }
}
