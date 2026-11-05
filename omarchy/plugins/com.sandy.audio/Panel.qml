import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "com.sandy.audio"
  ipcTarget: "com.sandy.audio"

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activeMediaPlayer: mediaService ? mediaService.activePlayer : null

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && isAudioSource(n)) {
        var name = n.name || ""
        if (name === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !isPlaybackStream(n)) continue
      // A tuning's output is a playback stream too, but it is the processing
      // itself rather than an application, so it does not belong in the list.
      if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue
      list.push(n)
    }
    return list
  }

  property var sinkAvailability: ({})
  property bool sinkAvailabilityLoaded: false

  // Identify true playback streams without reading node.properties here:
  // PwNode.properties is invalid until the node is bound, and reading it while
  // capture streams are appearing (for example, when Voxtype starts recording)
  // can destabilize Quickshell's Pipewire service. Quickshell versions differ
  // in how `type` is exposed (media.class, enum name, or numeric enum), but
  // playback streams consistently accept audio input from clients and publish
  // `isSink: true`; capture streams publish as stream sources.
  function isPlaybackStream(node) {
    return Model.isPlaybackStream(node)
  }

  function isAudioSource(node) {
    return Model.isAudioSource(node)
  }

  property var cachedAudioSinks: []
  property var cachedAudioSources: []

  // OUTPUT lists every sink (parity with INPUT listing every source):
  // unavailable ones (unplugged HDMI, absent jack) are dimmed but stay
  // selectable, so plugging a device in after opening the panel — or
  // force-routing to it — never strands the user with a single row.
  // The active sink keeps the selected highlight + bold label.
  // HDMI sinks whose ports are "not available" (cable unplugged) are excluded
  // entirely so the list doesn't show dead outputs.
  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream) {
        // Skip HDMI sinks when their port is not available
        if (n.name && n.name.indexOf("HDMI") >= 0 && !root.sinkAvailable(n)) {
          continue
        }
        list.push(n)
      }
    }
    return list
  }

  readonly property var rawAudioSinks: {
    var list = candidateSinks.slice()
    if (sink && list.indexOf(sink) < 0) list.unshift(sink)
    return list
  }

  readonly property var rawAudioSources: {
    var list = candidateSources.slice()
    if (source && list.indexOf(source) < 0) list.unshift(source)
    return list
  }

  readonly property var audioSinks: rawAudioSinks.length > 0 ? rawAudioSinks : cachedAudioSinks
  readonly property var audioSources: rawAudioSources.length > 0 ? rawAudioSources : cachedAudioSources

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio) list.push(candidateStreams[i])
    return list
  }

  // Feed Repeaters with panel-local snapshots instead of the live PipeWire
  // model. PipeWire can remove nodes while Quickshell is dispatching the
  // removal signal; rebuilding a Repeater from that signal path has crashed
  // in Quickshell's PipeWire service. The snapshot timer lets that mutation
  // settle first, and closed panels keep their repeaters detached entirely.
  property var displayAudioSinks: []
  property var displayAudioSources: []
  property var displayAudioStreams: []

  // Single-knob contract: the *default* sink (msi_dsp_input while the DSP
  // chain runs, the physical sink otherwise) is the one and only volume
  // authority. Display and real volume share the same 0-150% scale, exactly
  // like the volume keys, so no value can be silently capped.
  property string volumeSinkName: ""

  // Audio source mode: "speakers" | "headphones" | "both"
  // Controls where audio is routed when the user manually selects an output.
  property string audioSourceMode: "speakers"

  // DSP playback on/off. ON routes the default output through msi_dsp_input
  // so the DSP effect is heard; OFF routes straight to the physical sink.
  property bool dspEnabled: false
  property bool dspUserSet: false
  // Per-mode DSP memory. The top toggle remembers its state for each output
  // mode, so switching speakers -> headphones -> speakers restores what the
  // user last chose for that mode.
  property bool dspSpeakers: true
  property bool dspHeadphones: false
  property bool dspBoth: true
  // Physical output the user picked in the OUTPUT list (Speaker, an HDMI sink,
  // ...). "speakers" mode routes here when DSP is off, so choosing HDMI is not
  // overridden by the default Speaker sink.
  property string preferredSpeakerSink: ""
  // Startup routing runs before PipeWire nodes may be populated. Track whether
  // the restored state has been applied so onAudioSinksChanged can retry.
  property bool stateRestored: false
  property bool routingApplied: false

  // Headphones count as connected only when the physical port is available;
  // the sink node can linger while the jack is empty (port unavailable).
  readonly property bool headphonesConnected: {
    var hp = root.headphonesSinkNode()
    return !!hp && root.sinkAvailable(hp)
  }

  // When no headphones are connected the panel only offers Speakers, so mode
  // and DSP follow the speakers memory.
  readonly property string effectiveMode: root.headphonesConnected ? root.audioSourceMode : "speakers"

  // Find the speaker sink node (physical speakers). Falls back to an available
// HDMI sink, then the DSP input, when no physical speaker sink is present
// (headphones plugged in disables the internal speakers hardware).
  function speakerSinkNode() {
    // 1. The physical output the user explicitly chose in the OUTPUT list.
    if (root.preferredSpeakerSink !== "") {
      for (var p = 0; p < root.candidateSinks.length; p++) {
        var pref = root.candidateSinks[p]
        if (pref && pref.name === root.preferredSpeakerSink) return pref
      }
    }
    // 2. The internal speaker sink.
    for (var i = 0; i < root.candidateSinks.length; i++) {
      var n = root.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Speaker__sink") >= 0) return n
    }
    // 3. Any available HDMI sink.
    for (var j = 0; j < root.candidateSinks.length; j++) {
      var h = root.candidateSinks[j]
      if (h && h.name && h.name.indexOf("HDMI") >= 0 && root.sinkAvailable(h)) return h
    }
    return root.dspSinkNode()
  }

  // Find the headphones sink node (physical headphones).
  function headphonesSinkNode() {
    for (var i = 0; i < root.candidateSinks.length; i++) {
      var n = root.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Headphones__sink") >= 0) return n
    }
    return null
  }

  // Find the DSP playback sink (msi_dsp_input), if present.
  function dspSinkNode() {
    for (var i = 0; i < root.candidateSinks.length; i++) {
      var n = root.candidateSinks[i]
      if (n && n.name && String(n.name).indexOf("msi_dsp") === 0) return n
    }
    return null
  }

  // Remove the Speaker->Headphones loopback used by "both" mode. Called on
  // every mode change so leaving "both" stops the duplicate output. A shared
  // flock serialises this across the bar instances (one per monitor).
  function unloadBothLoopback(hp) {
    if (!hp) return
    var unload = "exec 9>/tmp/omarchy-audio-loopback.lock; flock 9; "
      + "pactl list short modules | awk -v s='" + hp.name
      + "' '$2==\"module-loopback\" && $0 ~ s {print $1}' | xargs -r -n1 pactl unload-module"
    Quickshell.execDetached(["bash", "-lc", unload])
  }

  // Replace the Speaker->Headphones loopback for "both" mode. Unload and load
  // run in one flock-protected shell so the async unload cannot race ahead and
  // drop the module we just created, and two bar instances cannot each leave a
  // duplicate module behind.
  function setBothLoopback(hp, spk) {
    if (!hp || !spk) return
    var cmd = "exec 9>/tmp/omarchy-audio-loopback.lock; flock 9; "
      + "pactl list short modules | awk -v s='" + hp.name
      + "' '$2==\"module-loopback\" && $0 ~ s {print $1}' | xargs -r -n1 pactl unload-module; "
      + "pactl load-module module-loopback sink=" + hp.name
      + " source=" + spk.name + ".monitor"
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  // Move the DSP chain output (msi_dsp_output) onto the chosen physical sink so
  // DSP playback follows whatever output the user picked instead of being stuck
  // on the speaker.
  function moveDspOutputTo(node) {
    if (!node) return
    var cmd = "sid=$(pactl list sink-inputs 2>/dev/null | awk '/^Sink Input #/{id=$3;sub(/#/,\"\",id)} /node.name = \"msi_dsp_output\"/{print id; exit}'); "
      + "tid=$(pactl list short sinks | awk -v n='" + node.name + "' '$2==n {print $1; exit}'); "
      + "[ -n \"$sid\" ] && [ -n \"$tid\" ] && pactl move-sink-input \"$sid\" \"$tid\" 2>/dev/null || true"
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function persistState(key, value) {
    Quickshell.execDetached(["omarchy-audio-panel-state", "set", key, value])
  }

  // Route the current mode. When DSP is on, apps go through msi_dsp_input and
  // the DSP output follows the chosen physical sink; when off, apps go
  // straight to the physical sink.
  function applyAudioRouting() {
    var spk = root.speakerSinkNode()
    var hp = root.headphonesSinkNode()
    var dsp = root.dspSinkNode()
    var mode = root.effectiveMode
    var physical = (mode === "headphones") ? hp : spk
    var useDsp = root.dspEnabled && dsp && physical

    if (mode === "headphones") {
      root.unloadBothLoopback(hp)
      if (!physical) return
      if (useDsp) { root.setDefaultSink(dsp); root.moveDspOutputTo(physical) }
      else root.setDefaultSink(physical)
      return
    }
    if (mode === "both") {
      if (!spk || !hp) { root.unloadBothLoopback(hp); return }
      if (useDsp) { root.setDefaultSink(dsp); root.moveDspOutputTo(spk) }
      else root.setDefaultSink(spk)
      root.setBothLoopback(hp, spk)
      return
    }
    // speakers mode
    root.unloadBothLoopback(hp)
    if (!physical) return
    if (useDsp) { root.setDefaultSink(dsp); root.moveDspOutputTo(physical) }
    else root.setDefaultSink(physical)
  }

  // Switch audio source mode. "speakers" | "headphones" | "both".
  function setAudioSourceMode(mode) {
    audioSourceMode = mode
    root.persistState("mode", mode)
    root.dspEnabled = root.dspForMode(root.effectiveMode)
    root.dspUserSet = true
    root.applyAudioRouting()
    root.showStatus("Audio mode: " + mode, "info")
  }

  // Remembered DSP state for a given output mode.
  function dspForMode(mode) {
    if (mode === "headphones") return root.dspHeadphones
    if (mode === "both") return root.dspBoth
    return root.dspSpeakers
  }

  function rememberDsp(mode, on) {
    if (mode === "headphones") root.dspHeadphones = on
    else if (mode === "both") root.dspBoth = on
    else root.dspSpeakers = on
    root.persistState("dsp_" + mode, on ? "on" : "off")
  }

  function setDspEnabled(on) {
    root.dspUserSet = true
    root.dspEnabled = on
    root.rememberDsp(root.effectiveMode, on)
    root.persistState("dsp", on ? "on" : "off")
    root.applyAudioRouting()
    root.showStatus("DSP playback: " + (on ? "on" : "off"), "info")
  }

// Selecting a row in OUTPUT changes the mode only. The DSP toggle stays the
// single control for DSP on/off, and its state follows the mode's memory.
  function selectSink(node) {
    if (!node) return
    var name = String(node.name || "")
    if (name.indexOf("__Headphones__sink") >= 0) {
      root.setAudioSourceMode("headphones")
    } else if (name.indexOf("msi_dsp") === 0) {
      root.setAudioSourceMode("speakers")
    } else {
      root.preferredSpeakerSink = name
      root.persistState("speaker_sink", name)
      root.setAudioSourceMode("speakers")
    }
  }

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name)) return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio)
        return n
    }
    return sink
  }

  // Re-resolve whenever the selected output changes; the timer below is only a
  // safety net for the tuning being applied or removed underneath us.
  onSinkChanged: {
    resolveVolumeSink()
  }

  function applyPanelState(raw) {
    var lines = String(raw || "").split("\n")
    var legacyDsp = null
    var sawSpeakersDsp = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var eq = line.indexOf("=")
      if (eq <= 0) continue
      var key = line.substring(0, eq)
      var value = line.substring(eq + 1)
      if (key === "mode" && (value === "speakers" || value === "headphones" || value === "both"))
        audioSourceMode = value
      else if (key === "dsp_speakers") { root.dspSpeakers = value === "on"; sawSpeakersDsp = true }
      else if (key === "dsp_headphones") root.dspHeadphones = value === "on"
      else if (key === "dsp_both") root.dspBoth = value === "on"
      else if (key === "speaker_sink") root.preferredSpeakerSink = value
      else if (key === "dsp") legacyDsp = value === "on"
    }
    // Back-compat: older state files only had a single `dsp` key.
    if (!sawSpeakersDsp && legacyDsp !== null) root.dspSpeakers = legacyDsp
    root.dspEnabled = root.dspForMode(root.effectiveMode)
    root.dspUserSet = true
    root.stateRestored = true
    if (root.routingApplied) {
      // State file changed after startup (another bar instance): apply now.
      root.applyAudioRouting()
    } else {
      root.tryApplyRestoredRouting()
    }
  }

  // Headphones plugged/unplugged: follow the physical jack. The card exposes
  // either the Speaker or the Headphones sink, never both, so the mode must
  // track the jack. DSP state still comes from each mode's own memory.
  onHeadphonesConnectedChanged: {
    if (!root.stateRestored) return
    if (root.headphonesConnected) {
      if (root.audioSourceMode === "speakers") root.audioSourceMode = "headphones"
    } else if (root.audioSourceMode !== "speakers") {
      root.audioSourceMode = "speakers"
    }
    root.persistState("mode", root.audioSourceMode)
    root.dspEnabled = root.dspForMode(root.effectiveMode)
    root.applyAudioRouting()
  }

  // Apply restored routing once the node required by the mode is available.
  function tryApplyRestoredRouting() {
    if (!root.stateRestored || root.routingApplied) return
    if (!root.sinkAvailabilityLoaded) return
    if (root.candidateSinks.length === 0) return
    var mode = root.effectiveMode
    if (mode === "headphones" && !root.headphonesSinkNode()) return
    if (mode === "both"
        && (!root.headphonesSinkNode() || !root.speakerSinkNode())) return
    root.routingApplied = true
    root.applyAudioRouting()
  }

  function resolveVolumeSink() {
    if (!volumeSinkProc.running) volumeSinkProc.running = true
  }

  // Internal units (0-1) match PipeWire sink volume. Display scales to 0-150
  // at the UI boundary (slider, OSD, percentage text).
  readonly property real outputVolume: {
    if (!volumeSink || !volumeSink.audio) return 0
    return Math.max(0, Math.min(1, volumeSink.audio.volume))
  }
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  // Status feedback for switch/test actions
  property string statusMessage: ""
  property string statusType: "info"  // info, success, error
  property bool statusVisible: false

  function showStatus(message, type) {
    statusMessage = message
    statusType = type || "info"
    statusVisible = true
    if (statusClearTimer.running) statusClearTimer.restart()
    else statusClearTimer.start()
  }

  function clearStatus() {
    statusVisible = false
    statusMessage = ""
  }

  function refreshDevices() {
    if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
    if (!volumeSinkProc.running) volumeSinkProc.running = true
    showStatus("Refreshing devices…", "info")
  }

  function playTestAudio() {
    if (!volumeSink || !volumeSink.name) {
      showStatus("No output sink available", "error")
      return
    }
    // Play a short test tone through the default sink (paplay uses PulseAudio/PipeWire)
    Quickshell.execDetached(["paplay", "-d", volumeSink.name, "/usr/share/sounds/alsa/Front_Center.wav"])
    showStatus("Test audio: " + volumeSink.name, "info")
  }

  onRawAudioSinksChanged: if (rawAudioSinks.length > 0) cachedAudioSinks = rawAudioSinks
  onRawAudioSourcesChanged: if (rawAudioSources.length > 0) cachedAudioSources = rawAudioSources

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "output"  — output slider + sink device list
  //   "input"   — input slider + source device list
  //   "streams" — per-app playback streams
  // selectedIndex semantics within a section:
  //   -1            → on the slider row (h/l adjusts volume, m/Enter mute)
  //   0..N-1        → on the Nth device/stream row
  // Visuals derive from hasCursor/current via CursorSurface, never
  // from containsMouse — that's what keeps the highlight unique across
  // keyboard + mouse like wifi does.
  property string focusSection: "output"
  property int selectedIndex: -1
  property bool cursorActive: false

  // "header" is a virtual section for the hero output mute toggle; it sits
  // above the output section so the speaker can be muted from the keyboard.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  // Only channels that actually exist get a vote. A box with no default source
  // would otherwise report "input unmuted" forever, leaving the hero switch
  // able to mute but never to unmute.
  readonly property bool hasOutput: !!(volumeSink && volumeSink.audio)
  readonly property bool hasInput: !!(source && source.audio)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)
  readonly property string toggleHint: anyAudible ? "Mute" : "Unmute"

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  function sectionCount(section) {
    if (section === "output") return displayAudioSinks.length
    if (section === "input") return displayAudioSources.length
    if (section === "streams") return displayAudioStreams.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "output") return true
    if (section === "input") return displayAudioSources.length > 0 || !!source
    if (section === "streams") return displayAudioStreams.length > 0
    return false
  }

  function sectionHasSlider(section) {
    if (section === "output") return true
    if (section === "input") return !!source
    return false  // stream rows carry their own sliders inline; not a section-level slider
  }

  // Order of visible sections, recomputed reactively so dropping a section
  // (e.g. no input devices) doesn't leave the cursor pointing at it.
  readonly property var visibleSections: {
    var list = []
    if (sectionVisible("output")) list.push("output")
    if (sectionVisible("input")) list.push("input")
    if (sectionVisible("streams")) list.push("streams")
    return list
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    if (focusSection === "header") {
      if (delta > 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(sections[0]) ? -1 : 0 }
      return
    }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(focusSection) ? -1 : 0; return }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1  // last device index
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0  // -1 = slider row

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; return }
      // Fall through to next section.
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      }
    } else {
      if (idx > floor) { selectedIndex = idx - 1; return }
      // Escape upward.
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        var prevMax = sectionCount(focusSection) - 1
        selectedIndex = prevMax >= 0 ? prevMax : (sectionHasSlider(focusSection) ? -1 : 0)
      } else {
        focusSection = "header"
      }
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    selectedIndex = -1
  }

  function moveSection(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    var current = sections.indexOf(focusSection)
    if (current < 0) current = delta > 0 ? -1 : 0
    var next = (current + delta + sections.length) % sections.length
    focusSection = sections[next]
    selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
    cursorActive = true
  }

  // Adjust the slider associated with the focused section. Output and
  // input sliders are real volume controls; on stream rows h/l adjusts
  // that stream's volume (so keyboard parity with the inline slider).
  // For device rows (selectedIndex >= 0 in output/input) h/l is a no-op
  // — the cursor is on a discrete row, not on the slider, and silently
  // moving the global slider would surprise the user.
  function adjustVolume(delta) {
    if (focusSection === "output" && selectedIndex === -1) {
      setOutputVolume(root.outputVolume * 150 + delta * 150)
      return
    }
    if (focusSection === "input" && selectedIndex === -1) {
      setInputVolume(inputVolume + delta)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0 && selectedIndex < displayAudioStreams.length) {
      var s = displayAudioStreams[selectedIndex]
      if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1.5, s.audio.volume + delta))
    }
  }

  // Enter/Space: activate whatever the cursor is on.
  function activateCursor() {
    if (focusSection === "header") { toggleAllMuted(); return }
    if (focusSection === "output") {
      if (selectedIndex === -1) { toggleOutputMute(); return }
      var sink = displayAudioSinks[selectedIndex]
      if (sink) setDefaultSink(sink)
      return
    }
    if (focusSection === "input") {
      if (selectedIndex === -1) { toggleInputMute(); return }
      var src = displayAudioSources[selectedIndex]
      if (src) setDefaultSource(src)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0) {
      var st = displayAudioStreams[selectedIndex]
      if (st && st.audio) st.audio.muted = !st.audio.muted
    }
  }

  onOpenedChanged: {
    if (opened) {
      // Re-read persisted mode/DSP so this instance matches what the other
      // monitor's bar last saved.
      if (root.stateRestored && !panelStateProc.running) panelStateProc.running = true
      refreshDisplayAudioModels()
      focusSection = "output"
      selectedIndex = -1  // first keyboard cursor reveal starts on the output slider
      cursorActive = false
      Qt.callLater(resetScroll)
    } else {
      clearDisplayAudioModels()
    }
  }

  // Clamp / repair the cursor whenever any list refreshes underneath us.
  onAudioSinksChanged: {
    scheduleDisplayAudioModelRefresh()
    root.tryApplyRestoredRouting()
    availabilityRefreshTimer.restart()
  }
  onAudioSourcesChanged: scheduleDisplayAudioModelRefresh()
  onAudioStreamsChanged: scheduleDisplayAudioModelRefresh()

  function listSnapshot(list) {
    return Model.listSnapshot(list)
  }

  function refreshDisplayAudioModels() {
    if (!opened) return
    // DSP input is controlled by the top toggle, not the OUTPUT list.
    var rawSinks = listSnapshot(audioSinks)
    var shownSinks = []
    for (var i = 0; i < rawSinks.length; i++) {
      var n = rawSinks[i]
      if (n && n.name && String(n.name).indexOf("msi_dsp") === 0) continue
      shownSinks.push(n)
    }
    displayAudioSinks = shownSinks
    displayAudioSources = listSnapshot(audioSources)
    displayAudioStreams = listSnapshot(audioStreams)
    clampCursor()
  }

  function scheduleDisplayAudioModelRefresh() {
    if (!opened) return
    audioModelRefreshTimer.restart()
  }

  function clearDisplayAudioModels() {
    audioModelRefreshTimer.stop()
    displayAudioSinks = []
    displayAudioSources = []
    displayAudioStreams = []
  }

  // Keep the keyboard-focused row inside the visible viewport of the
  // ScrollView. Each cursor target (slider rows, SinkRow, SourceRow,
  // StreamRow) calls this when it gains hasCursor. Without it, j/k can
  // walk the selection off-screen — wifi uses ListView.positionViewAtIndex
  // for this; we don't have that affordance with a multi-section Column.
  function resetScroll() {
    if (!scrollArea) return
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = 6
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24) || (root.focusSection === "output" && root.selectedIndex === -1)) {
      flick.contentY = 0
      return
    }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    // "header" is virtual and never appears in visibleSections, so it has to
    // be let through: muting republishes the PipeWire snapshot, and clamping
    // would knock the cursor off the hero switch on every toggle.
    if (focusSection === "header") return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = visibleSections[0]
      selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      return
    }
    var count = sectionCount(focusSection)
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0
    if (selectedIndex > count - 1) selectedIndex = Math.max(floor, count - 1)
    if (selectedIndex < floor) selectedIndex = floor
  }

  function outputIcon(volume) {
    // Match the old Waybar pulseaudio glyph set. The Material Design speaker
    // icons render visually smaller in JetBrainsMono Nerd Font.
    if (!sink || !sink.audio) return ""
    if (isHeadphones(sink)) return "󰋋"
    if (outputMuted) return ""
    var v = volume === undefined ? outputVolume : volume
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  function inputIcon() {
    if (!source || !source.audio) return "󰍭"
    return inputMuted ? "󰍭" : "󰍬"
  }

  // Playful mood-name for a given output volume. Mirrors the brightness
  // panel's brightnessName ladder; bands are wide enough that small
  // tweaks don't rename the room you're in.
  function outputVolumeName(volume, muted) {
    return Model.outputVolumeName(volume, muted)
  }

  // Display and sink volume share one 0-150 scale. Raising above zero also
  // unmutes so a muted sink can never look "stuck" at a level.
  function setOutputVolume(v) {
    if (!volumeSink || !volumeSink.audio) return outputVolume
    var display = Math.max(0, Math.min(150, v))
    volumeSink.audio.volume = display / 150
    if (display > 0 && volumeSink.audio.muted) volumeSink.audio.muted = false
    return display
  }

  function showVolumeOsd(volume) {
    if (!bar || !bar.shell) return
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: outputIcon(volume / 150),
      value: Math.round(volume)
    }))
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (volumeSink && volumeSink.audio) volumeSink.audio.muted = !volumeSink.audio.muted
  }

  function toggleInputMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  // The hero switch is the whole panel's on/off, so it carries both channels
  // at once. It reads as on while anything is still audible, which keeps
  // muting a single channel from the row below flipping the master switch.
  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput) volumeSink.audio.muted = mute
    if (hasInput) source.audio.muted = mute
  }

  // ---- Route verification state ----
  property string pendingSinkName: ""
  property int verifyRetryCount: 0
  property int verifyMaxRetries: 3
  property int verifyRetryDelay: 1000
  property string verifyStage: "idle"  // idle, checking-default, checking-streams, done

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      pendingSinkName = node.name
      verifyRetryCount = 0
      verifyStage = "idle"
      Quickshell.execDetached([
        "omarchy-audio-output-set-default",
        String(node.id),
        String(node.name)
      ])
      // Also refresh the volume target so volume keys stay on the right sink
      refreshVolumeSinkTarget()
      // Start bounded-retry route verification
      scheduleVerifyRetry()
    }
  }

  function scheduleVerifyRetry() {
    if (verifyRetryCount >= verifyMaxRetries) {
      finalizeVerification()
      return
    }
    verifyRetryCount++
    verifyRetryTimer.interval = verifyRetryDelay
    verifyRetryTimer.restart()
  }

  function runVerifyCheck() {
    verifyStage = "checking-default"
    verifySinkProc.running = true
  }

  function finalizeVerification() {
    if (verifyStage === "routing-verified") {
      root.showStatus("Output routed: " + root.friendlyDeviceLabel(pendingSinkName), "success")
    } else if (verifyStage === "default-changed") {
      root.showStatus("Default changed: " + root.friendlyDeviceLabel(pendingSinkName), "info")
    } else if (verifyStage === "routing-failed") {
      root.showStatus("Switch failed: routing incomplete", "error")
    } else {
      root.showStatus("Verification inconclusive", "error")
    }
    pendingSinkName = ""
    verifyRetryCount = 0
    verifyStage = "idle"
  }

  // Check default sink name via pactl
  Process {
    id: verifySinkProc
    command: ["pactl", "get-default-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var current = String(text).trim()
        if (current === pendingSinkName) {
          verifyStage = "checking-streams"
          verifyStreamProc.running = true
        } else {
          if (verifyRetryCount < verifyMaxRetries) {
            scheduleVerifyRetry()
          } else {
            verifyStage = "routing-failed"
            finalizeVerification()
          }
        }
      }
    }
  }

  // Check application stream destinations via pactl sink-inputs + sinks short
  Process {
    id: verifyStreamProc
    command: ["sh", "-c", "pactl list sink-inputs 2>/dev/null; echo '---SEPARATOR---'; pactl list sinks short 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = checkStreamRouting(text)
        if (result === "verified") {
          verifyStage = "routing-verified"
          finalizeVerification()
        } else if (result === "incomplete") {
          if (verifyRetryCount < verifyMaxRetries) {
            scheduleVerifyRetry()
          } else {
            verifyStage = "default-changed"
            finalizeVerification()
          }
        } else {
          // inconclusive
          if (verifyRetryCount < verifyMaxRetries) {
            scheduleVerifyRetry()
          } else {
            verifyStage = "default-changed"
            finalizeVerification()
          }
        }
      }
    }
  }

  // Parse pactl output to determine if app streams are routed to the target sink.
  // Returns "verified", "incomplete", or "inconclusive".
  function checkStreamRouting(raw) {
    var target = pendingSinkName || ""
    if (!target) return "inconclusive"

    var text = String(raw || "")
    var parts = text.split("---SEPARATOR---")
    var sinkInputsText = parts[0] || ""
    var sinksShortText = parts[1] || ""

    // Build sink index -> name map from "pactl list sinks short"
    var sinkIndexToName = {}
    var sinkLines = sinksShortText.split("\n")
    for (var i = 0; i < sinkLines.length; i++) {
      var m = sinkLines[i].match(/^(\d+)\t([^\t]+)/)
      if (m) {
        sinkIndexToName[m[1]] = m[2]
      }
    }

    // Parse sink-inputs entries
    var inputLines = sinkInputsText.split("\n")
    var currentId = ""
    var currentApp = ""
    var currentSinkIndex = ""
    var foundAppStream = false
    var allOnTarget = true

    function flushEntry() {
      if (currentId && currentApp && currentApp !== "EasyEffects") {
        foundAppStream = true
        var sinkName = sinkIndexToName[currentSinkIndex] || ""
        if (sinkName !== target && currentSinkIndex !== target) {
          allOnTarget = false
        }
      }
    }

    for (var i = 0; i < inputLines.length; i++) {
      var line = inputLines[i]

      var m = line.match(/^Sink Input #(\d+)/)
      if (m) {
        flushEntry()
        currentId = m[1]
        currentApp = ""
        currentSinkIndex = ""
        continue
      }

      m = line.match(/^\tSink: (\d+)/)
      if (m) {
        currentSinkIndex = m[1]
        continue
      }

      m = line.match(/application\.name = "([^"]+)"/)
      if (m) {
        currentApp = m[1]
        continue
      }
    }
    flushEntry()

    if (!foundAppStream) return "inconclusive"
    return allOnTarget ? "verified" : "incomplete"
  }

  // Refresh the physical volume target after a default-sink or profile change,
  // so volume keys always target the correct sink underneath any DSP chain.
  function refreshVolumeSinkTarget() {
    if (!volumeSinkProc.running) {
      volumeSinkProc.running = true
    }
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "omarchy-audio-input-set-default",
        String(node.id),
        String(node.name)
      ])
    }
  }

  function sinkAvailable(node) {
    if (!node || !node.name || !sinkAvailabilityLoaded) return true
    var name = String(node.name)
    return sinkAvailability[name] !== false
  }

  function updateSinkAvailability(raw) {
    sinkAvailability = Model.parseSinkAvailability(raw)
    sinkAvailabilityLoaded = true
    root.tryApplyRestoredRouting()
  }

  function friendlyDeviceLabel(text) {
    return Model.friendlyDeviceLabel(text)
  }

  function nodeLabel(node) {
    return Model.nodeLabel(node)
  }

  function nodeProps(node) {
    return Model.nodeProps(node)
  }

  function isHeadphones(node) {
    return Model.isHeadphones(node)
  }

  function sinkGlyph(node) {
    return Model.sinkGlyph(node)
  }

  // Detect virtual DSP sinks (e.g. msi_dsp_input, omarchy_speaker_tuning) that
  // are intermediates in the routing chain rather than physical outputs.
  // Null-safe: returns false if node is invalid or being destroyed.
  function isDspSink(node) {
    if (!node) return false
    try {
      var name = String(node.name || "")
      if (name.indexOf("msi_dsp") === 0 || name.indexOf("omarchy_speaker_tuning") === 0 || name.indexOf("easyeffects") === 0) {
        return true
      }
      var p = nodeProps(node)
      if (p && p["node.virtual"] === "true") return true
    } catch (e) {
      // Node may be mid-destruction; treat as non-DSP
      return false
    }
    return false
  }

  // Find the speaker sink node (physical speakers).
  function speakerSink() {
    for (var i = 0; i < root.candidateSinks.length; i++) {
      var n = root.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Speaker__sink") >= 0) return n
    }
    return null
  }

  // Find the headphones sink node (physical headphones).
  function headphonesSink() {
    for (var i = 0; i < root.candidateSinks.length; i++) {
      var n = root.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Headphones__sink") >= 0) return n
    }
    return null
  }

  // Check if a given sink node is the active default sink.
  function isSinkActive(sinkNode) {
    if (!sinkNode || !root.sink) return false
    return root.sink.id === sinkNode.id
  }

  function sourceGlyph(node) {
    return Model.sourceGlyph(node)
  }

  function friendlyStreamLabel(label) {
    return Model.friendlyStreamLabel(label)
  }

  function streamLabelKey(label) {
    return Model.streamLabelKey(label)
  }

  function streamLabelIsGeneric(label) {
    return Model.streamLabelIsGeneric(label)
  }

  function rawStreamLabel(node) {
    return Model.rawStreamLabel(node)
  }

  function mprisPlayerLabel(player) {
    return Model.mprisPlayerLabel(player)
  }

  function mprisPlayerIsProxy(player) {
    return Model.mprisPlayerIsProxy(player)
  }

  function streamRepresentsMprisPlayer(streamLabel, playerLabel) {
    return Model.streamRepresentsMprisPlayer(streamLabel, playerLabel)
  }

  function mprisLabelsFor(predicate) {
    return Model.mprisLabelsFor(mprisPlayers, predicate)
  }

  function matchingMprisStreamLabel(label) {
    return Model.matchingMprisStreamLabel(label, mprisPlayers)
  }

  function unmatchedMprisStreamLabel(label) {
    // Spotify exposes its PipeWire stream as "audio-src". For generic stream
    // names, use the one MPRIS player not already represented by another audio
    // stream (e.g. Chromium, or ALSA apps like cliamp).
    return Model.unmatchedMprisStreamLabel(label, mprisPlayers, displayAudioStreams)
  }

  function streamLabel(node) {
    return Model.streamLabel(node, mprisPlayers, displayAudioStreams)
  }

  function streamRepresentsPlayer(node, player) {
    return Model.streamRepresentsPlayer(node, player, mprisPlayers, displayAudioStreams)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.audioStreams }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: root.source
    enabled: root.opened && !!root.source
  }

  Process {
    id: sinkAvailabilityProc
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateSinkAvailability(text)
    }
  }

  // Single-knob contract: resolve the *default* sink itself (msi_dsp_input
  // while the DSP chain runs), NOT through it to the physical one. pactl
  // get-default-sink prints the sink name plainly.
  Process {
    id: volumeSinkProc
    command: ["pactl", "get-default-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.volumeSinkName = String(text).trim()
        if (!root.dspUserSet)
          root.dspEnabled = root.volumeSinkName.indexOf("msi_dsp") === 0
      }
    }
  }

  // Restore the persisted audio mode at startup. The panel also re-reads this
  // on open, which keeps the two monitor bar instances in sync (only one panel
  // is open at a time because it closes on pointer-leave).
  Process {
    id: panelStateProc
    command: ["omarchy-audio-panel-state", "all"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPanelState(text)
    }
  }
  Component.onCompleted: {
    if (!panelStateProc.running) panelStateProc.running = true
    if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
  }

  // Runs whether or not the panel is open: the bar shows and scrolls the output
  // volume too, so the default sink must stay resolved as the DSP chain comes
  // and goes (service restarts, daemon rebuilds).
  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resolveVolumeSink()
  }

  Timer {
    id: audioModelRefreshTimer
    interval: 75
    repeat: false
    onTriggered: root.refreshDisplayAudioModels()
  }

  // Re-probe port availability after sink changes so plugging/unplugging
  // headphones updates headphonesConnected (and the mode selector).
  Timer {
    id: availabilityRefreshTimer
    interval: 600
    repeat: false
    onTriggered: if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
  }

  // Auto-clear status messages after 3 seconds
  Timer {
    id: statusClearTimer
    interval: 3000
    repeat: false
    onTriggered: root.clearStatus()
  }

  // One-shot retry for route verification
  Timer {
    id: verifyRetryTimer
    interval: 1000
    repeat: false
    onTriggered: root.runVerifyCheck()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.outputIcon()
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleAllMuted()
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      if (!root.hasOutput) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var volume = root.setOutputVolume(root.outputVolume * 150 + wheel.steps * 5)
      root.showVolumeOsd(volume)
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
        else if (dx !== 0) root.adjustVolume(dx * 0.05)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        // 'm' mutes whatever the cursor is on: focused section's slider
        // for output/input, the focused stream for streams.
        if (t === "m" || t === "M") {
          if (!root.cursorActive) return
          if (root.focusSection === "streams" && root.selectedIndex >= 0
              && root.selectedIndex < root.displayAudioStreams.length) {
            var s = root.displayAudioStreams[root.selectedIndex]
            if (s && s.audio) s.audio.muted = !s.audio.muted
          } else if (root.focusSection === "input") {
            root.toggleInputMute()
          } else {
            root.toggleOutputMute()
          }
        } else if (t === "r" || t === "R") {
          root.refreshDevices()
        } else if (t === "t" || t === "T") {
          root.playTestAudio()
        }
      }

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

          // ---------- Hero: speaker icon · title/status ----------
          Item {
            id: heroItem
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

            // Status only — the switch owns muting, mouse and keyboard alike.
            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.outputIcon()
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.outputMuted ? 0.5 : 1.0
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            // Compact on/off switch on the trailing edge of the hero, and the
            // header's only cursor target. Checked means something is still
            // audible, so muting everything reads as switching audio off.
            ToggleSwitch {
              id: powerSwitch
              checked: root.anyAudible
              hasCursor: root.headerHasCursor
              foreground: root.bar.foreground
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onHovered: function(on) { if (on) root.setHeaderCursor() }
              onToggled: root.toggleAllMuted()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: root.bar.fontFamily
              }
            }

            // Quick-switch: Speaker / Headphones. Always visible so the user
            // can change outputs without unplugging/replugging headphones.
            Row {
              id: speakerSwitcher
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                id: speakerSwitcherSpeaker
                textFormat: Text.PlainText
                text: "󰓃 Speakers"
                color: isSinkActive(speakerSink()) ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: isSinkActive(speakerSink())
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var s = root.speakerSink()
                    if (s) root.setDefaultSink(s)
                  }
                }
              }

              Text {
                id: speakerSwitcherHeadphones
                textFormat: Text.PlainText
                text: "󰋋 Headphones"
                color: isSinkActive(headphonesSink()) ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: isSinkActive(headphonesSink())
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    var s = root.headphonesSink()
                    if (s) root.setDefaultSink(s)
                  }
                }
              }
            }

            Column {
              id: heroLabels
              anchors.left: speakerSwitcher.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: powerSwitch.width + Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Audio"
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
                text: root.outputVolumeName(
                  outputSlider.dragging ? outputSlider.liveValue : root.outputVolume,
                  root.outputMuted
                ).toUpperCase()
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

          // ---- Audio source mode selection ----
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(sourceModeHeader.implicitHeight, sourceModeRow.implicitHeight)

              PanelSectionHeader {
                id: sourceModeHeader
                text: "AUDIO MODE"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: sourceModeRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                // Speakers mode button
                Row {
                  id: modeSpeakersRow
                  spacing: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: root.audioSourceMode === "speakers" ? "✓" : "○"
                    color: root.audioSourceMode === "speakers" ? "#8aff8a" : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "󰓃 Speakers"
                    color: root.audioSourceMode === "speakers" ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.audioSourceMode === "speakers"
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setAudioSourceMode("speakers")
                    }
                  }
                }

                // Headphones mode button
                Row {
                  id: modeHeadphonesRow
                  visible: root.headphonesConnected
                  spacing: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: root.audioSourceMode === "headphones" ? "✓" : "○"
                    color: root.audioSourceMode === "headphones" ? "#8aff8a" : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "󰋋 Headphones"
                    color: root.audioSourceMode === "headphones" ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.audioSourceMode === "headphones"
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setAudioSourceMode("headphones")
                    }
                  }
                }

                // Both mode button
                Row {
                  id: modeBothRow
                  visible: root.headphonesConnected
                  spacing: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: root.audioSourceMode === "both" ? "✓" : "○"
                    color: root.audioSourceMode === "both" ? "#8aff8a" : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "󰢻 Both"
                    color: root.audioSourceMode === "both" ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.audioSourceMode === "both"
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setAudioSourceMode("both")
                    }
                  }
                }
              }
            }

            // DSP playback toggle: ON routes speakers/both through
            // msi_dsp_input so the effect is heard; OFF bypasses it.
            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "󰓃 DSP Playback"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                checked: root.dspEnabled
                foreground: root.bar.foreground
                anchors.verticalCenter: parent.verticalCenter
                onToggled: root.setDspEnabled(!root.dspEnabled)
              }

              Text {
                textFormat: Text.PlainText
                text: root.dspEnabled ? "On" : "Off"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          // ---- Output devices ----
          PanelSeparator {
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(outputHeader.implicitHeight, outputPercent.implicitHeight)

              PanelSectionHeader {
                id: outputHeader
                text: "OUTPUT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: outputPercent
                textFormat: Text.PlainText
                text: Math.round(outputSlider.dragging ? outputSlider.liveValue : outputVolume * 150) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.outputMuted ? 0.5 : 1.0
              }
            }

            // Status feedback line (switch result, test audio, refresh)
            Text {
              id: statusText
              textFormat: Text.PlainText
              text: root.statusMessage
              color: root.statusType === "error" ? "#ff5555" : (root.statusType === "success" ? "#8aff8a" : Qt.darker(root.bar.foreground, 1.4))
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.statusType !== "info"
              anchors.left: parent.left
              anchors.right: parent.right
              visible: root.statusVisible
              elide: Text.ElideRight
            }

            CursorSurface {
              id: outputSliderRow
              width: parent.width
              height: outputSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(outputSliderRow)
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: outputSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: 150
                step: 1
                value: root.outputVolume * 150
                opacity: root.outputMuted ? 0.5 : 1.0
                enabled: !!root.sink

                onMoved: function(v) { root.setOutputVolume(v) }
                onRightClicked: root.toggleOutputMute()
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "output"
                  root.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: root.displayAudioSinks

              SinkRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }

          // ---- Input ----
          PanelSeparator {
            visible: root.displayAudioSources.length > 0 || !!root.source
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.displayAudioSources.length > 0 || !!root.source

            Item {
              width: parent.width
              implicitHeight: Math.max(microphoneHeader.implicitHeight, microphonePercent.implicitHeight)

              PanelSectionHeader {
                id: microphoneHeader
                text: "INPUT"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: microphonePercent
                textFormat: Text.PlainText
                text: Math.round((inputSlider.dragging ? inputSlider.liveValue : root.inputVolume) * 100) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.inputMuted ? 0.5 : 1.0
              }
            }

            CursorSurface {
              id: inputSliderRow
              visible: !!root.source
              width: parent.width
              height: inputControls.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(inputSliderRow)
              foreground: root.bar.foreground
              outline: true

              Column {
                id: inputControls
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(5)

                PanelSlider {
                  id: inputSlider
                  bar: root.bar
                  width: parent.width
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: root.inputVolume
                  opacity: root.inputMuted ? 0.5 : 1.0
                  enabled: !!root.source

                  onMoved: function(v) { root.setInputVolume(v) }
                  onRightClicked: root.toggleInputMute()
                }

                Rectangle {
                  width: parent.width
                  height: Math.max(Style.space(5), Style.spacing.xs)
                  color: Util.alpha(root.bar.foreground, 0.18)
                  opacity: root.inputMuted ? 0.35 : 1.0

                  Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, inputPeakMonitor.peak))
                    color: root.bar.foreground
                    Behavior on width { NumberAnimation { duration: 70 } }
                  }
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "input"
                  root.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: root.displayAudioSources

              SourceRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }

          // ---- Per-app streams ----
          PanelSeparator {
            visible: root.displayAudioStreams.length > 0
            foreground: root.bar.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.displayAudioStreams.length > 0

            PanelSectionHeader {
              text: "SOURCES"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.displayAudioStreams

              StreamRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
              }
            }
          }
        }
      }
    }
  }

  // ---- Reusable inline components ----

  // Output device row — cursor target inside the "output" section. Mouse
  // hover updates the panel cursor at the root; visuals come entirely
  // from hasCursor/current via CursorSurface, never from containsMouse.
  component SinkRow: CursorSurface {
    id: sinkRow
    required property var node
    required property int rowIndex

    readonly property bool isValidNode: !!node
    readonly property bool isActive: isValidNode && root.sink && node && root.sink.id === node.id
    // Availability is advisory only (dimming); the row stays clickable.
    readonly property bool isAvailable: isValidNode && root.sinkAvailable(node)
    readonly property bool isDsp: isValidNode && root.isDspSink(node)
    readonly property string statusText: isValidNode
      ? (isDsp ? (isActive ? "Active (DSP)" : (isAvailable ? "Avail (DSP)" : "Disc (DSP)"))
      : (isActive ? "Active" : (isAvailable ? "Available" : "Disconnected")))
      : ""
    readonly property string statusColor: isValidNode
      ? (isActive ? "#ffffff" : (isAvailable ? "#888888" : "#555555"))
      : "#555555"
    hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sinkRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: sinkInner.implicitHeight + Style.spacing.xl
    opacity: isAvailable ? 1.0 : 0.45

    Row {
      id: sinkInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.sinkGlyph(sinkRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: sinkRow.statusText
        color: sinkRow.statusColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: sinkRow.isActive
        width: Style.space(96)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: root.nodeLabel(sinkRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: sinkRow.isActive
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(96) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "output"
        root.selectedIndex = sinkRow.rowIndex
      }
      onClicked: root.selectSink(sinkRow.node)
    }
  }

  // Input device row — sibling of SinkRow for the "input" section.
  component SourceRow: CursorSurface {
    id: sourceRow
    required property var node
    required property int rowIndex

    readonly property bool isActive: root.source && node && root.source.id === node.id
    hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sourceRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: sourceInner.implicitHeight + Style.spacing.xl

    Row {
      id: sourceInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: root.sourceGlyph(sourceRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: root.nodeLabel(sourceRow.node)
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: sourceRow.isActive
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "input"
        root.selectedIndex = sourceRow.rowIndex
      }
      onClicked: root.setDefaultSource(sourceRow.node)
    }
  }

  // Per-app stream row — cursor target inside the "streams" section.
  // The stream has its own slider inline, so h/l from the keyboard
  // adjusts THIS stream's volume (not the global output) when the cursor
  // sits on this row. Enter/Space mutes the stream.
  component StreamRow: CursorSurface {
    id: streamRow
    required property var node
    required property int rowIndex

    readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
    readonly property bool streamMuted: node && node.audio ? node.audio.muted : false
    readonly property bool isActive: root.streamRepresentsPlayer(node, root.activeMediaPlayer)

    hasCursor: root.cursorActive && root.focusSection === "streams" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(streamRow)
    current: isActive
    foreground: root.bar.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: streamColumn.implicitHeight + Style.spacing.xl

    Column {
      id: streamColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: streamMuteIcon
          textFormat: Text.PlainText
          text: streamRow.streamMuted ? "󰝟" : "󰕾"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (streamRow.node && streamRow.node.audio)
                streamRow.node.audio.muted = !streamRow.node.audio.muted
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: root.streamLabel(streamRow.node)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: streamRow.isActive
          elide: Text.ElideRight
          width: parent.width - streamMuteIcon.width - streamPct.width - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: streamPct
          textFormat: Text.PlainText
          text: Math.round(streamRow.streamVolume * 100) + "%"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0
        }
      }

      PanelSlider {
        bar: root.bar
        width: parent.width
        minimum: 0
        maximum: 1.5
        step: 0.05
        value: streamRow.streamVolume
        opacity: streamRow.streamMuted ? 0.5 : 1.0

        onMoved: function(v) {
          if (streamRow.node && streamRow.node.audio) streamRow.node.audio.volume = v
        }
        onRightClicked: {
          if (streamRow.node && streamRow.node.audio)
            streamRow.node.audio.muted = !streamRow.node.audio.muted
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      propagateComposedEvents: true
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "streams"
        root.selectedIndex = streamRow.rowIndex
      }
    }
  }
}
