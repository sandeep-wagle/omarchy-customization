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
  id: panelRoot
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
      // The DSP chain is the panel's own plumbing, not an app the user can
      // control. Hide both its input and output nodes from the stream list.
      if (String(n.name || "").indexOf("msi_dsp") === 0) continue
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
        if (n.name && n.name.indexOf("HDMI") >= 0 && !panelRoot.sinkAvailable(n)) {
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

  // Single-knob contract: one canonical level owns the output, and every
  // stage that can attenuate it (the DSP input while the chain runs, the
  // physical sink otherwise) is driven from that value. Switching DSP or the
  // default sink can therefore never move the level the user sees.
  //
  // Canonical units are 0-1.5, matching PipeWire/wireplumber: 1.0 = 100%,
  // 1.5 = 150%. The UI displays `canonical * 100`, so the panel, the volume
  // keys, and `pactl` all report the same number.
  property string volumeSinkName: ""
  property real canonicalOutputVolume: 0
  property bool canonicalOutputMuted: false
  property bool canonicalOutputLoaded: false
  property bool outputStateRestored: false
  // Set while the panel itself writes sink volumes, so the change handler
  // cannot mistake our own write for an external volume-key press.
  property bool applyingCanonicalOutput: false
  // Routing and default-sink changes ripple asynchronously through PipeWire.
  // Ignore adoption for a short window so a stale target cannot overwrite the
  // remembered value.
  property bool outputSettle: false

  // Audio source mode: "speakers" | "headphones"
  // Controls where audio is routed when the user manually selects an output.
  // "both" is intentionally absent: this HDA codec's Speaker and Headphones
  // ports live in mutually exclusive profiles and can never sound together.
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

  // Headphones are detected from the card's own Headphones port, which stays
  // listed in `pactl list cards` even while the Speaker profile is active.
  // Reading the jack (not a sink node) keeps the mode toggle usable across a
  // profile switch: after switching to Speaker the Headphones sink is gone,
  // but the jack is still plugged, so Speakers/Headphones must stay selectable.
  property bool headphonesJackPresent: false
  property bool jackPresenceLoaded: false
  // True once the state file supplied an explicit `mode`. Without it the panel
  // has no user choice to restore and must follow the jack instead of assuming
  // speakers (that assumption is what left "Speakers" selected after a reboot
  // with the headphones plugged in).
  property bool storedModeKnown: false
  // Anti-oscillation guards. The card profile, the state file, the DSP service
  // and the jack probe all feed each other, so a single stale read used to
  // start a loop that flipped the output every few hundred ms. Every one of
  // those paths now has to wait out a quiet period before it may act again.
  property double lastModeWriteAt: 0
  property string lastProfilePort: ""
  property double lastProfileAt: 0
  property double lastJackChangeAt: 0
  property bool lastServiceDsp: false
  property double lastServiceDspAt: 0
  readonly property bool headphonesConnected: panelRoot.headphonesJackPresent

  // When no headphones are connected the panel only offers Speakers, so mode
  // and DSP follow the speakers memory.
  readonly property string effectiveMode: panelRoot.headphonesConnected ? panelRoot.audioSourceMode : "speakers"

  // Guard so sink-changed ripples cannot loop back into routing.
  property bool routingInProgress: false

  // Find the speaker sink node (physical speakers). It only exists while the
  // Speaker card profile is active, so returning null here is expected until
  // ensureOutputProfile("Speaker") has switched the profile. Never fall back to
  // the headphones sink: doing so silently routed "Speakers" to the headphones
  // and made "Both" loop a sink into itself (the loud feedback screech).
  function speakerSinkNode() {
    // 1. The physical output the user explicitly chose in the OUTPUT list.
    if (panelRoot.preferredSpeakerSink !== "") {
      for (var p = 0; p < panelRoot.candidateSinks.length; p++) {
        var pref = panelRoot.candidateSinks[p]
        if (pref && pref.name === panelRoot.preferredSpeakerSink) return pref
      }
    }
    // 2. The internal speaker sink.
    for (var i = 0; i < panelRoot.candidateSinks.length; i++) {
      var n = panelRoot.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Speaker__sink") >= 0) return n
    }
    // 3. No physical speaker sink. When the card profile is mid-switch this is
    //    expected; the caller retries rather than jumping to HDMI, which would
    //    silently send "Speakers" to the monitor while the profile settles.
    //    An HDMI output is only used when explicitly chosen in OUTPUT (step 1).
    return null
  }

  // Find the headphones sink node (physical headphones).
  function headphonesSinkNode() {
    for (var i = 0; i < panelRoot.candidateSinks.length; i++) {
      var n = panelRoot.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Headphones__sink") >= 0) return n
    }
    return null
  }

  // Find the DSP playback sink (msi_dsp_input), if present.
  function dspSinkNode() {
    for (var i = 0; i < panelRoot.candidateSinks.length; i++) {
      var n = panelRoot.candidateSinks[i]
      if (n && n.name && String(n.name).indexOf("msi_dsp") === 0) return n
    }
    return null
  }

  // Remove any stale Speaker<->Headphones loopback left by the old "both" mode,
  // which fed a sink's monitor back into the same sink and produced a very loud
  // feedback howl. Called on every mode change so a stale module cannot persist.
  function cleanupAudioLoopbacks() {
    var cmd = "LC_ALL=C pactl list short modules | awk '$2==\"module-loopback\"{print $1, $0}' "
      + "| grep -E '__Speaker__sink|__Headphones__sink' | awk '{print $1}' "
      + "| xargs -r -n1 pactl unload-module"
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  // Switch the sound card profile so the requested physical port becomes the
  // active output. The Speaker and Headphones ports sit in mutually exclusive
  // profiles on this HDA codec, so this is what actually changes the sound
  // between the internal speakers and the headphones jack. The helper script
  // is idempotent: it does nothing when the right profile is already active.
  function ensureOutputProfile(port) {
    // A profile restart tears down every sink, so it must never run twice for
    // the same target in quick succession: that is an audible gap and, for
    // some players, a paused stream. The helper is idempotent; this guard only
    // stops repeat launches of it.
    var now = Date.now()
    if (port === panelRoot.lastProfilePort && now - panelRoot.lastProfileAt < 3000) return
    panelRoot.lastProfilePort = port
    panelRoot.lastProfileAt = now
    Quickshell.execDetached(["bash", "-lc",
      "\"$HOME/.config/omarchy/plugins/com.sandy.audio/switch-output-profile\" " + port])
  }

  // Switching the card profile destroys the old sink and builds a new one at
  // its default 100% level. Two guards keep that from producing a blast: hold
  // off live-value adoption for the switch, and zero the freshly created sink
  // in applyAudioRouting before it is routed to (see there).
  function beginOutputSwitch(port) {
    var target = port === "Headphones"
      ? panelRoot.headphonesSinkNode()
      : panelRoot.speakerSinkNode()
    if (target) return
    panelRoot.outputSettle = true
  }

  // The Speakers control always means the internal speakers. Clearing a
  // remembered HDMI pick prevents "Speakers" from silently keeping audio on a
  // monitor while the panel claims the speakers are selected.
  function setSpeakersMode() {
    if (panelRoot.preferredSpeakerSink !== "") {
      panelRoot.preferredSpeakerSink = ""
      panelRoot.persistState("speaker_sink", "")
    }
    panelRoot.setAudioSourceMode("speakers")
  }

  // Move the DSP chain output (msi_dsp_output) onto the chosen physical sink so
  // DSP playback follows whatever output the user picked instead of being stuck
  // on the speaker. A card profile switch re-creates nodes and WirePlumber can
  // re-home the DSP output afterwards (seen landing on HDMI), so the move is
  // re-asserted a few times by dspFollowTimer.
  property string dspFollowTargetName: ""
  // Tell the DSP service which sink the chain should feed. Without this the
  // service guesses, and its guess fell through to HDMI while the panel said
  // Headphones, so the sound left the chosen output. The service validates the
  // name against its live sink list, so a stale entry is harmless.
  function setDspTarget(name) {
    var cmd = "mkdir -p \"$HOME/.config/msi-center\"; printf '%s' '"
      + String(name).replace(/'/g, "") + "' > \"$HOME/.config/msi-center/dsp-target\""
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function moveDspOutputTo(node) {
    if (!node) return
    panelRoot.dspFollowTargetName = String(node.name)
    panelRoot.setDspTarget(node.name)
    panelRoot.applyDspOutputMove()
    dspFollowTimer.attempts = 0
    dspFollowTimer.start()
  }

  function applyDspOutputMove() {
    if (panelRoot.dspFollowTargetName === "") return
    var cmd = "sid=$(pactl list sink-inputs 2>/dev/null | awk '/^Sink Input #/{id=$3;sub(/#/,\"\",id)} /node.name = \"msi_dsp_output\"/{print id; exit}'); "
      + "tid=$(pactl list short sinks | awk -v n='" + panelRoot.dspFollowTargetName + "' '$2==n {print $1; exit}'); "
      + "cur=$(pactl list sink-inputs 2>/dev/null | awk '/^Sink Input #/{id=$3;sub(/#/,\"\",id)} id==sid && /^\tSink: /{print $2}' sid=\"$sid\"); "
      + "[ -n \"$sid\" ] && [ -n \"$tid\" ] && [ \"$cur\" != \"$tid\" ] && pactl move-sink-input \"$sid\" \"$tid\" 2>/dev/null || true"
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function persistState(key, value) {
    Quickshell.execDetached(["omarchy-audio-panel-state", "set", key, value])
  }

  // Route the current mode. When DSP is on, apps go through msi_dsp_input and
  // the DSP output follows the chosen physical sink; when off, apps go
  // straight to the physical sink. Re-entrant-safe via routingInProgress so
  // sink-changed ripples cannot loop.
  function applyAudioRouting() {
    if (panelRoot.routingInProgress) return
    panelRoot.routingInProgress = true
    var spk = panelRoot.speakerSinkNode()
    var hp = panelRoot.headphonesSinkNode()
    var dsp = panelRoot.dspSinkNode()
    var mode = panelRoot.effectiveMode
    var physical = (mode === "headphones") ? hp : spk

    // The DSP's own virtual sink is a processing stage, never a physical
    // output. Treating it as one would route the chain back into itself, which
    // is a cycle and the source of the loud howl.
    if (physical && String(physical.name).indexOf("msi_dsp") === 0) physical = null

    // A stale loopback from the removed "both" mode would keep feeding a sink
    // into itself long after the mode is gone. Clear it on every routing pass.
    panelRoot.cleanupAudioLoopbacks()

    // The sink for this mode does not exist until the matching card profile is
    // active. Leave routing unapplied and poll briefly: the profile switch is
    // asynchronous, so the node appears a moment later.
    if (!physical) {
      panelRoot.routingInProgress = false
      routeRetryTimer.start()
      return
    }

    var useDsp = !!(panelRoot.dspEnabled && dsp)

    // Stage the remembered level on every stage before the default moves, so
    // the switch never exposes a different sink's stale volume. First sink the
    // brand-new node to silence: a fresh ALSA sink starts at 100% and would
    // otherwise play a burst before the canonical value lands.
    if (panelRoot.canonicalOutputLoaded && physical.audio) {
      physical.audio.volume = 0
      physical.audio.muted = true
    }
    panelRoot.applyCanonicalOutput(useDsp)

    if (useDsp) {
      panelRoot.setDefaultSink(dsp)
      panelRoot.moveDspOutputTo(physical)
    } else {
      panelRoot.setDefaultSink(physical)
      // Keep the chain's target truthful even while DSP is off, so enabling it
      // later links straight to the output the user already chose.
      panelRoot.setDspTarget(physical.name)
    }
    panelRoot.applyingCanonicalOutput = false
    // Safety net: a switch guard may have muted these stages before their
    // volumes were known. Once routing is settled they must match the user's
    // mute choice.
    if (!panelRoot.outputMuted) {
      if (dsp && dsp.audio) dsp.audio.muted = false
      if (physical && physical.audio) physical.audio.muted = false
    }
    panelRoot.routingApplied = true
    panelRoot.routingInProgress = false
  }

  // Switch audio source mode. "speakers" | "headphones".
  // The card profile must change before routing: the Speaker and Headphones
  // sinks never coexist, so routing without the profile switch would leave the
  // desired sink missing and the sound on the wrong port.
  function setAudioSourceMode(mode) {
    if (mode !== "speakers" && mode !== "headphones") mode = "speakers"
    panelRoot.captureOutputState()
    panelRoot.beginOutputSwitch(mode === "headphones" ? "Headphones" : "Speaker")
    audioSourceMode = mode
    panelRoot.lastModeWriteAt = Date.now()
    panelRoot.persistState("mode", mode)
    panelRoot.dspEnabled = panelRoot.dspForMode(panelRoot.effectiveMode)
    panelRoot.dspUserSet = true
    panelRoot.syncServiceDsp(panelRoot.dspEnabled)
    panelRoot.ensureOutputProfile(mode === "headphones" ? "Headphones" : "Speaker")
    panelRoot.applyAudioRouting()
    panelRoot.showStatus("Audio mode: " + mode, "info")
  }

  // Remembered DSP state for a given output mode.
  function dspForMode(mode) {
    if (mode === "headphones") return panelRoot.dspHeadphones
    return panelRoot.dspSpeakers
  }

  function rememberDsp(mode, on) {
    if (mode === "headphones") panelRoot.dspHeadphones = on
    else panelRoot.dspSpeakers = on
    panelRoot.persistState("dsp_" + mode, on ? "on" : "off")
  }

  // The DSP service has its own enable flag and pins the physical speaker to
  // 100% while that flag is on (the chain carries the level). The panel must
  // tell it when DSP is toggled, or the service re-pins the speaker to 100%
  // and the volume jumps the moment DSP is switched off.
  property bool serviceDspKnown: false
  property bool serviceDspState: false

  function syncServiceDsp(on) {
    var now = Date.now()
    if (panelRoot.serviceDspKnown && panelRoot.serviceDspState === on) return
    // The service switches the default sink when it flips, so a rapid alternation
    // here is a second oscillation source. Ignore flips inside the quiet window.
    if (now - panelRoot.lastServiceDspAt < 3000 && panelRoot.lastServiceDsp !== on) return
    panelRoot.lastServiceDspAt = now
    panelRoot.lastServiceDsp = on
    panelRoot.serviceDspKnown = true
    panelRoot.serviceDspState = on
    var cmd = "mkdir -p \"$HOME/.config/msi-center\"; printf '" + (on ? "1" : "0")
      + "' > \"$HOME/.config/msi-center/dsp-enabled\"; printf '" + (on ? "ENABLE" : "DISABLE")
      + "\\n' | socat - UNIX-CONNECT:/tmp/msi_dsp.sock >/dev/null 2>&1 || true"
    Quickshell.execDetached(["bash", "-lc", cmd])
    // The service changes the default sink itself on ENABLE/DISABLE (to the
    // chain or to its own speaker pick). Re-assert the panel's routing once it
    // has finished, so HDMI/headphones and the remembered level survive.
    serviceRerouteTimer.restart()
  }

  function setDspEnabled(on) {
    panelRoot.captureOutputState()
    panelRoot.dspUserSet = true
    panelRoot.dspEnabled = on
    panelRoot.syncServiceDsp(on)
    panelRoot.rememberDsp(panelRoot.effectiveMode, on)
    panelRoot.persistState("dsp", on ? "on" : "off")
    panelRoot.applyAudioRouting()
    panelRoot.showStatus("DSP playback: " + (on ? "on" : "off"), "info")
  }

// Selecting a row in OUTPUT changes the mode only. The DSP toggle stays the
// single control for DSP on/off, and its state follows the mode's memory.
  function selectSink(node) {
    if (!node) return
    var name = String(node.name || "")
    if (name.indexOf("__Headphones__sink") >= 0) {
      panelRoot.setAudioSourceMode("headphones")
    } else if (name.indexOf("msi_dsp") === 0) {
      panelRoot.setAudioSourceMode("speakers")
    } else {
      panelRoot.preferredSpeakerSink = name
      panelRoot.persistState("speaker_sink", name)
      panelRoot.setAudioSourceMode("speakers")
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
    var storedVolume = null
    var storedMuted = null
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var eq = line.indexOf("=")
      if (eq <= 0) continue
      var key = line.substring(0, eq)
      var value = line.substring(eq + 1)
      if (key === "mode" && (value === "speakers" || value === "headphones")) {
        // Persistence is asynchronous, so a read can arrive after a newer
        // decision was already made. Let the newer one win.
        if (Date.now() - panelRoot.lastModeWriteAt > 2000) audioSourceMode = value
        panelRoot.storedModeKnown = true
      }
      // Older state files may still hold the removed "both" mode. Headphones is
      // the closest surviving behaviour, and the jack probe corrects it if the
      // headphones are not actually plugged.
      else if (key === "mode" && value === "both") {
        audioSourceMode = "headphones"
        panelRoot.storedModeKnown = true
      }
      else if (key === "dsp_speakers") { panelRoot.dspSpeakers = value === "on"; sawSpeakersDsp = true }
      else if (key === "dsp_headphones") panelRoot.dspHeadphones = value === "on"
      // "dsp_both" is read only to keep old files parseable; the mode is gone.
      else if (key === "dsp_both") panelRoot.dspBoth = value === "on"
      else if (key === "speaker_sink") panelRoot.preferredSpeakerSink = value
      else if (key === "output_volume") {
        var parsed = Number(value)
        if (isFinite(parsed) && parsed >= 0) storedVolume = Math.min(150, parsed)
      }
      else if (key === "output_muted") storedMuted = value === "on"
      else if (key === "dsp") legacyDsp = value === "on"
    }
    // Back-compat: older state files only had a single `dsp` key.
    if (!sawSpeakersDsp && legacyDsp !== null) panelRoot.dspSpeakers = legacyDsp
    panelRoot.dspEnabled = panelRoot.dspForMode(panelRoot.effectiveMode)
    panelRoot.dspUserSet = true
    panelRoot.syncServiceDsp(panelRoot.dspEnabled)

    // Restore the remembered output level once. Later reads of the state file
    // only sync mode/DSP; the live sink already drives the level, so a stale
    // file (persistence is debounced) can never pull the slider backwards.
    if (!panelRoot.outputStateRestored) {
      if (storedVolume !== null) {
        panelRoot.canonicalOutputVolume = storedVolume / 100
      } else {
        panelRoot.canonicalOutputVolume = panelRoot.liveOutputVolume
      }
      if (storedMuted !== null) panelRoot.canonicalOutputMuted = storedMuted
      else panelRoot.canonicalOutputMuted = panelRoot.liveOutputMuted
      panelRoot.canonicalOutputLoaded = true
      panelRoot.outputStateRestored = true
      panelRoot.persistOutputState()
    }

    panelRoot.stateRestored = true
    if (panelRoot.routingApplied) {
      // State file changed after startup (another bar instance): apply now.
      panelRoot.applyAudioRouting()
    } else {
      panelRoot.tryApplyRestoredRouting()
    }
  }

  // Headphones plugged/unplugged: follow the physical jack. The card exposes
  // either the Speaker or the Headphones sink, never both, so the mode must
  // track the jack. Plugging in switches to headphones; unplugging falls back
  // to speakers. DSP state comes from each mode's own memory.
  // `prevJackPresent` lets the handler tell a fresh plug (follow it) from a
  // probe after the user already chose speakers while the jack stayed in.
  property bool prevJackPresent: false

  function handleJackPresence(present) {
    var wasLoaded = panelRoot.jackPresenceLoaded
    var wasPresent = panelRoot.prevJackPresent
    panelRoot.headphonesJackPresent = present
    panelRoot.jackPresenceLoaded = true
    panelRoot.prevJackPresent = present

    if (!wasLoaded) {
      // First probe of the session: only force speakers when nothing is plugged.
      // A plugged jack keeps whatever mode the state file restored, because the
      // user may have chosen Speakers while leaving the headphones connected.
      if (present && panelRoot.storedModeKnown) {
        // Keep the mode, but the card may already be on the wrong profile (the
        // DSP service or WirePlumber switch it during login). Re-assert it so a
        // stored "headphones" cannot come back as a Speaker profile.
        if (!panelRoot.physicalOutputSink()) {
          panelRoot.beginOutputSwitch(panelRoot.audioSourceMode === "headphones" ? "Headphones" : "Speaker")
          panelRoot.ensureOutputProfile(panelRoot.audioSourceMode === "headphones" ? "Headphones" : "Speaker")
        }
        panelRoot.applyAudioRouting()
        return
      }
    } else if (present === wasPresent) {
      return
    } else if (Date.now() - panelRoot.lastJackChangeAt < 2000) {
      // A reading that contradicts the one just acted on is a probe artifact
      // (card reconfiguring during a profile switch), not a real plug event.
      return
    }

    panelRoot.lastJackChangeAt = Date.now()
    panelRoot.lastModeWriteAt = Date.now()
    panelRoot.beginOutputSwitch(present ? "Headphones" : "Speaker")
    panelRoot.audioSourceMode = present ? "headphones" : "speakers"
    panelRoot.persistState("mode", panelRoot.audioSourceMode)
    panelRoot.dspEnabled = panelRoot.dspForMode(panelRoot.effectiveMode)
    panelRoot.syncServiceDsp(panelRoot.dspEnabled)
    panelRoot.ensureOutputProfile(present ? "Headphones" : "Speaker")
    panelRoot.applyAudioRouting()
    panelRoot.tryApplyRestoredRouting()
  }

  // Apply restored routing once the node required by the mode is available.
  function tryApplyRestoredRouting() {
    if (!panelRoot.stateRestored || panelRoot.routingApplied) return
    if (!panelRoot.sinkAvailabilityLoaded) return
    if (!panelRoot.jackPresenceLoaded) return
    if (panelRoot.candidateSinks.length === 0) return
    if (!panelRoot.physicalOutputSink()) {
      // The saved mode's sink needs the matching card profile. Switch it, then
      // let applyAudioRouting's retry pick up the new node.
      panelRoot.ensureOutputProfile(panelRoot.effectiveMode === "headphones" ? "Headphones" : "Speaker")
      panelRoot.applyAudioRouting()
      return
    }
    panelRoot.applyAudioRouting()
  }

  function resolveVolumeSink() {
    if (!volumeSinkProc.running) volumeSinkProc.running = true
  }

  // Live values of whatever sink PipeWire currently calls the default. They
  // feed the canonical state (external volume keys) but never drive the UI
  // directly.
  readonly property real liveOutputVolume: {
    if (!volumeSink || !volumeSink.audio) return 0
    return Math.max(0, Math.min(1.5, volumeSink.audio.volume))
  }
  readonly property bool liveOutputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false

  // True when the default sink is the DSP input, i.e. the DSP stage is the one
  // carrying the level. The physical sink then sits at unity so it does not
  // attenuate a second time.
  readonly property bool outputThroughDsp:
    String(volumeSink && volumeSink.name ? volumeSink.name : "").indexOf("msi_dsp") === 0

  // Canonical units are 0-1.5; the UI multiplies by 100.
  readonly property real outputVolume: canonicalOutputLoaded ? canonicalOutputVolume : liveOutputVolume
  readonly property bool outputMuted: canonicalOutputLoaded ? canonicalOutputMuted : liveOutputMuted
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  // The physical output that actually carries the sound for the current mode.
  // Never returns the DSP node: that is a processing stage, not a speaker.
  function physicalOutputSink() {
    var node = panelRoot.effectiveMode === "headphones"
      ? panelRoot.headphonesSinkNode()
      : panelRoot.speakerSinkNode()
    if (node && String(node.name || "").indexOf("msi_dsp") === 0) return null
    return node
  }

  // Drive every attenuation stage from the canonical value. `throughDsp` is
  // passed explicitly during a DSP toggle because `volumeSink` still points at
  // the old default until PipeWire acknowledges the switch.
  function applyCanonicalOutput(throughDsp) {
    if (!panelRoot.canonicalOutputLoaded) return
    if (throughDsp === undefined) throughDsp = panelRoot.outputThroughDsp
    var volume = Math.max(0, Math.min(1.5, panelRoot.canonicalOutputVolume))
    var muted = panelRoot.canonicalOutputMuted
    var dsp = panelRoot.dspSinkNode()
    var physical = panelRoot.physicalOutputSink()

    panelRoot.applyingCanonicalOutput = true
    if (dsp && dsp.audio) {
      dsp.audio.volume = volume
      dsp.audio.muted = muted
    }
    if (physical && physical.audio) {
      // One attenuation stage only: the active one. The idle stage stays at
      // unity/unmuted so it cannot scale the signal twice.
      physical.audio.volume = throughDsp ? 1.0 : volume
      physical.audio.muted = throughDsp ? false : muted
    }
    panelRoot.applyingCanonicalOutput = false

    // Hold off adoption while the graph and default sink settle.
    panelRoot.outputSettle = true
    outputSettleTimer.restart()
  }

  // The stage that is supposed to carry the level right now. Used to reject
  // stale sink resolutions: while DSP is on, the physical sink sits at unity
  // and must never be mistaken for the user's level.
  function intendedOutputSink() {
    var dsp = panelRoot.dspSinkNode()
    var physical = panelRoot.physicalOutputSink()
    if (panelRoot.dspEnabled && dsp && physical) return dsp
    return physical
  }

  // Adopt an external change (volume keys, another mixer) from the live sink.
  function adoptLiveOutput() {
    if (!panelRoot.outputStateRestored) return
    if (panelRoot.applyingCanonicalOutput || panelRoot.routingInProgress || panelRoot.outputSettle) return
    if (!panelRoot.volumeSink || panelRoot.volumeSink !== panelRoot.intendedOutputSink()) return
    panelRoot.canonicalOutputLoaded = true
    panelRoot.canonicalOutputVolume = panelRoot.liveOutputVolume
    panelRoot.canonicalOutputMuted = panelRoot.liveOutputMuted
    panelRoot.persistOutputState()
  }

  // Snapshot the live sink before a routing change, so the level the user is
  // hearing right now becomes the value carried to the next stage.
  function captureOutputState() {
    if (!panelRoot.canonicalOutputLoaded) return
    if (panelRoot.outputSettle || panelRoot.routingInProgress) return
    if (!panelRoot.volumeSink || !panelRoot.volumeSink.audio) return
    if (panelRoot.volumeSink !== panelRoot.intendedOutputSink()) return
    panelRoot.canonicalOutputVolume = panelRoot.liveOutputVolume
    panelRoot.canonicalOutputMuted = panelRoot.liveOutputMuted
    panelRoot.persistOutputState()
  }

  function persistOutputState() {
    outputStatePersistTimer.restart()
  }

  onLiveOutputVolumeChanged: panelRoot.adoptLiveOutput()
  onLiveOutputMutedChanged: panelRoot.adoptLiveOutput()
  // Only refresh the target here. Routing owns the staging call, so a stale
  // default-sink name cannot re-assert the wrong attenuation stage.
  onVolumeSinkChanged: panelRoot.resolveVolumeSink()

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

  function restartAudioService() {
    Quickshell.execDetached(["systemctl", "--user", "restart", "pipewire.service", "pipewire-pulse.service"])
    showStatus("Restarting audio service…", "info")
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
  readonly property string toggleHint: outputMuted ? "Unmute output" : "Mute output"

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"
  // Hearing-safety cue: anything past 100% gets an amber fill and percentage.
  readonly property color overdriveColor: "#ffb454"
  readonly property color secondaryForeground: Qt.darker(panelRoot.barForeground, 1.2)

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
      setOutputVolume(panelRoot.outputVolume * 100 + delta * 100)
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
    if (focusSection === "header") { toggleOutputMute(); return }
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
      if (panelRoot.stateRestored && !panelStateProc.running) panelStateProc.running = true
      if (!jackPresenceProc.running) jackPresenceProc.running = true
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
  // Re-apply routing only when the sink *topology* changes (a device appears,
  // disappears, or is renamed). Quickshell rebuilds the node list on ordinary
  // volume/mute changes too; routing on those would re-assert the canonical
  // volume and swallow every physical volume-key press.
  property string sinkTopologySignature: ""

  function currentSinkTopologySignature() {
    var parts = []
    var list = panelRoot.candidateSinks
    for (var i = 0; i < list.length; i++) {
      var n = list[i]
      if (!n) continue
      parts.push(String(n.id) + ":" + String(n.name))
    }
    parts.sort()
    return parts.join("|")
  }

  onAudioSinksChanged: {
    scheduleDisplayAudioModelRefresh()
    panelRoot.tryApplyRestoredRouting()
    var signature = panelRoot.currentSinkTopologySignature()
    if (signature !== panelRoot.sinkTopologySignature) {
      panelRoot.sinkTopologySignature = signature
      if (panelRoot.stateRestored) panelRoot.applyAudioRouting()
    }
    availabilityRefreshTimer.restart()
  }
  onAudioSourcesChanged: scheduleDisplayAudioModelRefresh()
  onAudioStreamsChanged: scheduleDisplayAudioModelRefresh()

  function listSnapshot(list) {
    return Model.listSnapshot(list)
  }

  function refreshDisplayAudioModels() {
    if (!opened) return
    var rawSinks = listSnapshot(audioSinks)
    var shownSinks = []
    for (var i = 0; i < rawSinks.length; i++) {
      var n = rawSinks[i]
      if (!n || !n.name) continue
      var name = String(n.name)
      // Skip DSP input - controlled by DSP toggle inside OUTPUT section
      if (name.indexOf("msi_dsp") === 0) continue
      // Speaker sink: always visible
      if (name.indexOf("__Speaker__sink") >= 0) { shownSinks.push(n); continue }
      // Headphones sink: only when physically connected
      if (name.indexOf("__Headphones__sink") >= 0) {
        if (panelRoot.headphonesConnected) shownSinks.push(n)
        continue
      }
      // HDMI sink: only when port available (cable plugged in)
      if (name.indexOf("HDMI") >= 0) {
        if (panelRoot.sinkAvailable(n)) shownSinks.push(n)
        continue
      }
      // Any other physical sink: show it
      shownSinks.push(n)
    }

    // Inputs: drop the DSP playback monitor. It is panel plumbing and reads as
    // a second, broken microphone.
    var rawSources = listSnapshot(audioSources)
    var shownSources = []
    for (var s = 0; s < rawSources.length; s++) {
      var src = rawSources[s]
      if (!src || !src.name) continue
      var srcName = String(src.name)
      if (srcName.indexOf("msi_dsp") === 0) continue
      var srcLabel = panelRoot.nodeLabel(src).toLowerCase()
      if (srcLabel.indexOf("dsp playback") !== -1 || srcLabel.indexOf("msi dsp") !== -1) continue
      shownSources.push(src)
    }

    var rawStreams = listSnapshot(audioStreams)
    var shownStreams = []
    for (var t = 0; t < rawStreams.length; t++) {
      var stream = rawStreams[t]
      if (!stream || !stream.name) continue
      if (String(stream.name).indexOf("msi_dsp") === 0) continue
      var streamName = panelRoot.streamLabel(stream).toLowerCase()
      if (streamName.indexOf("dsp playback") !== -1 || streamName.indexOf("msi dsp") !== -1) continue
      shownStreams.push(stream)
    }

    displayAudioSinks = shownSinks
    displayAudioSources = shownSources
    displayAudioStreams = shownStreams
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
    if (maxY <= Style.space(24) || (panelRoot.focusSection === "output" && panelRoot.selectedIndex === -1)) {
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
    if (isHeadphones(sink)) return "\uf025"
    if (outputMuted) return ""
    var v = volume === undefined ? outputVolume / 1.5 : volume
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  function inputIcon() {
    if (!source || !source.audio) return "\uf131"
    return inputMuted ? "\uf131" : "\uf130"
  }

  // Playful mood-name for a given output volume. Mirrors the brightness
  // panel's brightnessName ladder; bands are wide enough that small
  // tweaks don't rename the room you're in.
  function outputVolumeName(volume, muted) {
    return Model.outputVolumeName(volume, muted)
  }

  // Canonical units are 0-1.5, so 150% display is 1.5 on the sink: exactly
  // what the volume keys and `pactl` report. Raising above zero also unmutes
  // so a muted sink can never look "stuck" at a level.
  function setOutputVolume(v) {
    var display = Math.max(0, Math.min(150, v))
    panelRoot.canonicalOutputLoaded = true
    panelRoot.canonicalOutputVolume = display / 100
    if (display > 0) panelRoot.canonicalOutputMuted = false
    panelRoot.applyCanonicalOutput()
    panelRoot.persistOutputState()
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
    var next = !panelRoot.outputMuted
    panelRoot.canonicalOutputLoaded = true
    panelRoot.canonicalOutputMuted = next
    panelRoot.applyCanonicalOutput()
    panelRoot.persistOutputState()
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
      panelRoot.showStatus("Output routed: " + panelRoot.friendlyDeviceLabel(pendingSinkName), "success")
    } else if (verifyStage === "default-changed") {
      panelRoot.showStatus("Default changed: " + panelRoot.friendlyDeviceLabel(pendingSinkName), "info")
    } else if (verifyStage === "routing-failed") {
      panelRoot.showStatus("Switch failed: routing incomplete", "error")
    } else {
      panelRoot.showStatus("Verification inconclusive", "error")
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
    panelRoot.tryApplyRestoredRouting()
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
    for (var i = 0; i < panelRoot.candidateSinks.length; i++) {
      var n = panelRoot.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Speaker__sink") >= 0) return n
    }
    return null
  }

  // Find the headphones sink node (physical headphones).
  function headphonesSink() {
    for (var i = 0; i < panelRoot.candidateSinks.length; i++) {
      var n = panelRoot.candidateSinks[i]
      if (n && n.name && n.name.indexOf("__Headphones__sink") >= 0) return n
    }
    return null
  }

  // Check if a given sink node is the active default sink.
  function isSinkActive(sinkNode) {
    if (!sinkNode || !panelRoot.sink) return false
    return panelRoot.sink.id === sinkNode.id
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

  PwObjectTracker { objects: panelRoot.candidateSinks }
  PwObjectTracker { objects: panelRoot.candidateSources }
  PwObjectTracker { objects: panelRoot.audioStreams }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: panelRoot.source
    enabled: panelRoot.opened && !!panelRoot.source
  }

  Process {
    id: sinkAvailabilityProc
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: panelRoot.updateSinkAvailability(text)
    }
  }

  // Probe the codec's own ALSA Headphone Jack control. This is independent of
  // the active card profile (the PipeWire port availability flips while the
  // Speaker profile is active, which made the mode chase its own tail), and it
  // is read-only: values=on means something is plugged in.
  Process {
    id: jackPresenceProc
    command: ["bash", "-lc",
      "amixer -c 0 cget numid=15 2>/dev/null | tail -1 | sed 's/.*values=//'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text).trim()
        if (value !== "on" && value !== "off") return
        panelRoot.handleJackPresence(value === "on")
      }
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
        panelRoot.volumeSinkName = String(text).trim()
        if (!panelRoot.dspUserSet)
          panelRoot.dspEnabled = panelRoot.volumeSinkName.indexOf("msi_dsp") === 0
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
      onStreamFinished: panelRoot.applyPanelState(text)
    }
  }
  Component.onCompleted: {
    if (!panelStateProc.running) panelStateProc.running = true
    if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
    if (!jackPresenceProc.running) jackPresenceProc.running = true
  }

  // Give the default-sink switch time to propagate before adopting live sink
  // values again. Without this, the sink that is being replaced can report a
  // stale volume and overwrite the remembered one.
  Timer {
    id: outputSettleTimer
    interval: 1200
    repeat: false
    onTriggered: {
      panelRoot.outputSettle = false
      panelRoot.adoptLiveOutput()
    }
  }

  // The DSP service applies its own default-sink choice 300ms after ENABLE/
  // DISABLE. Let it finish, then put routing back on the user's selection.
  Timer {
    id: serviceRerouteTimer
    interval: 700
    repeat: false
    onTriggered: {
      if (panelRoot.stateRestored) panelRoot.applyAudioRouting()
    }
  }

  // Coalesce persistence writes: dragging the slider must not spawn one
  // helper process per pixel.
  Timer {
    id: outputStatePersistTimer
    interval: 250
    repeat: false
    onTriggered: {
      panelRoot.persistState("output_volume", String(Math.round(panelRoot.canonicalOutputVolume * 100)))
      panelRoot.persistState("output_muted", panelRoot.canonicalOutputMuted ? "on" : "off")
      // The DSP service stores its own level as real/1.5 and re-applies it
      // after a graph rebuild. Keep that file truthful so a service restart
      // cannot snap the volume back to a stale value.
      var serviceLevel = (panelRoot.canonicalOutputVolume / 1.5).toFixed(4)
      Quickshell.execDetached(["bash", "-lc",
        "mkdir -p \"$HOME/.config/msi-center\" && printf '%s' '" + serviceLevel
        + "' > \"$HOME/.config/msi-center/msi-volume\""])
    }
  }

  Timer {
    interval: 5000
    running: panelRoot.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
      if (!jackPresenceProc.running) jackPresenceProc.running = true
    }
  }

  // Jack presence must be tracked even while the panel is closed: plugging
  // headphones should switch the mode on its own, exactly like the old sink-node
  // heuristic did (that one broke once the Speaker profile hid the node).
  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!jackPresenceProc.running) jackPresenceProc.running = true
  }

  // Runs whether or not the panel is open: the bar shows and scrolls the output
  // volume too, so the default sink must stay resolved as the DSP chain comes
  // and goes (service restarts, daemon rebuilds).
  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: panelRoot.resolveVolumeSink()
  }

  Timer {
    id: audioModelRefreshTimer
    interval: 75
    repeat: false
    onTriggered: panelRoot.refreshDisplayAudioModels()
  }

  // A card profile switch tears down and re-creates the sink node. Poll until
  // the wanted physical sink exists, then route once, and give up after ~10s.
  Timer {
    id: routeRetryTimer
    interval: 500
    repeat: true
    running: false
    property int attempts: 0
    onTriggered: {
      attempts++
      if (panelRoot.physicalOutputSink()) {
        stop()
        attempts = 0
        panelRoot.applyAudioRouting()
      } else if (attempts >= 20) {
        stop()
        attempts = 0
        // The wanted output never appeared. Release the mute guard and put the
        // canonical level back so audio is not left silenced.
        panelRoot.applyingCanonicalOutput = false
        panelRoot.applyCanonicalOutput(panelRoot.dspEnabled)
        panelRoot.showStatus("Selected output is not available", "error")
      } else {
        // The sink is missing, so the card is on the wrong profile. Re-assert
        // it: at boot the DSP service and WirePlumber can switch profiles after
        // the panel already routed, which otherwise leaves "Headphones" stored
        // but the Speaker profile active. The helper is idempotent and cheap.
        panelRoot.ensureOutputProfile(
          panelRoot.effectiveMode === "headphones" ? "Headphones" : "Speaker")
      }
    }
  }



  // Re-assert the DSP output's physical target for a few seconds after a
  // routing change. Bounded: it stops as soon as it has run 4 times.
  Timer {
    id: dspFollowTimer
    interval: 1500
    repeat: true
    running: false
    property int attempts: 0
    onTriggered: {
      attempts++
      panelRoot.applyDspOutputMove()
      if (attempts >= 4) { stop(); attempts = 0 }
    }
  }




  // Re-probe port availability after sink changes so plugging/unplugging
  // headphones updates the mode selector.
  Timer {
    id: availabilityRefreshTimer
    interval: 600
    repeat: false
    onTriggered: {
      if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
      if (!jackPresenceProc.running) jackPresenceProc.running = true
    }
  }

  // Auto-clear status messages after 3 seconds
  Timer {
    id: statusClearTimer
    interval: 3000
    repeat: false
    onTriggered: panelRoot.clearStatus()
  }

  // One-shot retry for route verification
  Timer {
    id: verifyRetryTimer
    interval: 1000
    repeat: false
    onTriggered: panelRoot.runVerifyCheck()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: panelRoot.bar
    text: panelRoot.outputIcon()
    onPressed: function(b) {
      if (b === Qt.RightButton) panelRoot.toggleAllMuted()
      else panelRoot.toggle()
    }

    onWheelMoved: function(delta) {
      if (!panelRoot.hasOutput) return
      var wheel = Util.wheelSteps(panelRoot.wheelAccumulator, delta)
      panelRoot.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var volume = panelRoot.setOutputVolume(panelRoot.outputVolume * 100 + wheel.steps * 5)
      panelRoot.showVolumeOsd(volume)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: panelRoot
    bar: panelRoot.bar
    open: panelRoot.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!panelRoot.cursorActive) { panelRoot.cursorActive = true; return }
        if (dy !== 0) panelRoot.moveCursor(dy)
        else if (dx !== 0) panelRoot.adjustVolume(dx * 0.05)
      }
      onActivateRequested: if (panelRoot.cursorActive) panelRoot.activateCursor()
      onCloseRequested: panelRoot.close()
      onTabRequested: function(direction) { panelRoot.switchPanel(direction) }
      onTextKey: function(t) {
        // 'm' mutes whatever the cursor is on: focused section's slider
        // for output/input, the focused stream for streams.
        if (t === "m" || t === "M") {
          if (!panelRoot.cursorActive) return
          if (panelRoot.focusSection === "streams" && panelRoot.selectedIndex >= 0
              && panelRoot.selectedIndex < panelRoot.displayAudioStreams.length) {
            var s = panelRoot.displayAudioStreams[panelRoot.selectedIndex]
            if (s && s.audio) s.audio.muted = !s.audio.muted
          } else if (panelRoot.focusSection === "input") {
            panelRoot.toggleInputMute()
          } else {
            panelRoot.toggleOutputMute()
          }
        } else if (t === "r" || t === "R") {
          panelRoot.refreshDevices()
        } else if (t === "t" || t === "T") {
          panelRoot.playTestAudio()
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
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, muteButton.implicitHeight, restartServiceButton.implicitHeight)

            // Status only — the icon button owns muting, mouse and keyboard alike.
            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: panelRoot.outputIcon()
              color: panelRoot.barForeground
              font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
              font.pixelSize: Style.font.display
              opacity: panelRoot.outputMuted ? 0.5 : 1.0
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            // Hero action buttons on the right, spaced evenly so they never
            // overlap: mute (output on/off) and restart audio service.
            Row {
              id: heroActions
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              // Icon button, not a switch: a switch cannot say whether "on"
              // means muted or audible. The glyph does. It is still the
              // header's only keyboard cursor target.
              PanelActionButton {
                id: muteButton
                iconText: panelRoot.outputIcon()
                tooltipText: panelRoot.toggleHint
                foreground: panelRoot.barForeground
                fontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                fontSize: Style.font.title
                hasCursor: panelRoot.headerHasCursor
                onHovered: function(on) { if (on) panelRoot.setHeaderCursor() }
                onClicked: panelRoot.toggleOutputMute()
              }

              // Service control: restart PipeWire when audio breaks.
              PanelActionButton {
                id: restartServiceButton
                iconText: "\uf0e7"
                tooltipText: "Restart audio service"
                foreground: panelRoot.barForeground
                fontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                fontSize: Style.font.title
                size: Style.space(26)
                bordered: true
                onClicked: panelRoot.restartAudioService()
              }
            }

            // Quick-switch: Speaker / Headphones. Always visible so the user can
            // change outputs without unplugging/replugging headphones. Both go
            // through setAudioSourceMode, which also switches the card profile;
            // changing only the default sink cannot reach the other port.
            Row {
              id: speakerSwitcher
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                id: speakerSwitcherSpeaker
                textFormat: Text.PlainText
                text: "\uf028 Speakers"
                color: panelRoot.effectiveMode === "speakers" ? panelRoot.barForeground : panelRoot.secondaryForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.body
                font.bold: panelRoot.effectiveMode === "speakers"
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panelRoot.setSpeakersMode()
                }
              }

              Text {
                id: speakerSwitcherHeadphones
                textFormat: Text.PlainText
                text: "\uf025 Headphones"
                color: panelRoot.effectiveMode === "headphones" ? panelRoot.barForeground : panelRoot.secondaryForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.body
                font.bold: panelRoot.effectiveMode === "headphones"
                anchors.verticalCenter: parent.verticalCenter
                visible: panelRoot.headphonesConnected
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panelRoot.setAudioSourceMode("headphones")
                }
              }
            }

            Column {
              id: heroLabels
              anchors.left: speakerSwitcher.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: heroActions.width + Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Audio"
                color: panelRoot.barForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                id: heroLabel
                textFormat: Text.PlainText
                text: panelRoot.outputVolumeName(
                  outputSlider.dragging ? outputSlider.liveValue / 150 : panelRoot.outputVolume / 1.5,
                  panelRoot.outputMuted
                ).toUpperCase()
                color: panelRoot.secondaryForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
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
            foreground: panelRoot.barForeground
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
                foreground: panelRoot.barForeground
                fontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
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
                    text: panelRoot.audioSourceMode === "speakers" ? "✓" : "○"
                    color: panelRoot.audioSourceMode === "speakers" ? "#8aff8a" : panelRoot.barForeground
                    font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "\uf028 Speakers"
                    color: panelRoot.audioSourceMode === "speakers" ? panelRoot.barForeground : panelRoot.secondaryForeground
                    font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: panelRoot.audioSourceMode === "speakers"
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: panelRoot.setSpeakersMode()
                    }
                  }
                }

                // Headphones mode button
                Row {
                  id: modeHeadphonesRow
                  visible: panelRoot.headphonesConnected
                  spacing: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    text: panelRoot.audioSourceMode === "headphones" ? "✓" : "○"
                    color: panelRoot.audioSourceMode === "headphones" ? "#8aff8a" : panelRoot.barForeground
                    font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "\uf025 Headphones"
                    color: panelRoot.audioSourceMode === "headphones" ? panelRoot.barForeground : panelRoot.secondaryForeground
                    font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: panelRoot.audioSourceMode === "headphones"
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: panelRoot.setAudioSourceMode("headphones")
                    }
                  }
                }
              }
            }


          }

          // ---- Output devices ----
          PanelSeparator {
            visible: panelRoot.headphonesConnected
            foreground: panelRoot.barForeground
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
                foreground: panelRoot.barForeground
                fontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: outputPercent
                textFormat: Text.PlainText
                text: Math.round(outputSlider.dragging ? outputSlider.liveValue : outputVolume * 100) + "%"
                color: (outputSlider.dragging ? outputSlider.liveValue : outputVolume * 100) > 100
                  ? panelRoot.overdriveColor
                  : panelRoot.secondaryForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                opacity: panelRoot.outputMuted ? 0.5 : 1.0
              }
            }

            // Status feedback line (switch result, test audio, refresh)
            Text {
              id: statusText
              textFormat: Text.PlainText
              text: panelRoot.statusMessage
              color: panelRoot.statusType === "error" ? "#ff5555" : (panelRoot.statusType === "success" ? "#8aff8a" : panelRoot.secondaryForeground)
              font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: panelRoot.statusType !== "info"
              anchors.left: parent.left
              anchors.right: parent.right
              visible: panelRoot.statusVisible
              elide: Text.ElideRight
            }

            CursorSurface {
              id: outputSliderRow
              width: parent.width
              height: outputSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: panelRoot.cursorActive && panelRoot.focusSection === "output" && panelRoot.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) panelRoot.ensureCursorVisible(outputSliderRow)
              foreground: panelRoot.barForeground
              outline: true

              readonly property real displayValue: outputSlider.dragging
                ? outputSlider.liveValue
                : panelRoot.outputVolume * 100
              // Track geometry mirrors PanelSlider: the track is inset by half
              // a knob at each end. 100% sits at two thirds of a 0-150 range.
              readonly property real trackLeft: outputSlider.x + outputSlider.knobSize / 2
              readonly property real trackWidth: Math.max(0, outputSlider.width - outputSlider.knobSize)
              readonly property real thresholdX: trackLeft + trackWidth * (100 / 150)
              readonly property real valueX: trackLeft + trackWidth * Math.min(1, displayValue / 150)

              PanelSlider {
                id: outputSlider
                bar: panelRoot.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0
                maximum: 150
                step: 1
                value: panelRoot.outputVolume * 100
                opacity: panelRoot.outputMuted ? 0.5 : 1.0
                enabled: !!panelRoot.sink

                onMoved: function(v) { panelRoot.setOutputVolume(v) }
                onRightClicked: panelRoot.toggleOutputMute()
              }

              // Amber overdrive segment: only the part past 100%.
              Rectangle {
                anchors.verticalCenter: outputSlider.verticalCenter
                x: outputSliderRow.thresholdX
                width: Math.max(0, outputSliderRow.valueX - outputSliderRow.thresholdX)
                height: outputSlider.trackHeight
                radius: height / 2
                color: panelRoot.overdriveColor
                opacity: panelRoot.outputMuted ? 0.5 : 1.0
                visible: width > 0
              }

              // 100% tick. The hearing-safety boundary stays visible even when
              // the fill is still below it.
              Rectangle {
                anchors.verticalCenter: outputSlider.verticalCenter
                width: Math.max(1, Style.space(2))
                height: outputSlider.trackHeight + Style.space(6)
                radius: 1
                color: panelRoot.secondaryForeground
                opacity: panelRoot.outputMuted ? 0.5 : 1.0
                x: outputSliderRow.thresholdX - width / 2
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  panelRoot.cursorActive = true
                  panelRoot.focusSection = "output"
                  panelRoot.selectedIndex = -1
                }
              }
            }

            // DSP playback toggle: ON routes output through msi_dsp_input so
            // the effect is heard; OFF bypasses it straight to the sink.
            // A switch is correct here: it is a real on/off setting. No "On"
            // text beside it — the thumb already carries the state.
            Item {
              width: parent.width
              implicitHeight: Math.max(dspIcon.implicitHeight, dspLabel.implicitHeight, dspSwitch.implicitHeight)

              Text {
                id: dspIcon
                textFormat: Text.PlainText
                text: "\uf1de"
                color: panelRoot.barForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.title
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: dspLabel
                textFormat: Text.PlainText
                text: "DSP Playback"
                color: panelRoot.barForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                anchors.left: dspIcon.right
                anchors.leftMargin: Style.space(8)
                anchors.right: dspSwitch.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                id: dspSwitch
                checked: panelRoot.dspEnabled
                foreground: panelRoot.barForeground
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                onToggled: panelRoot.setDspEnabled(!panelRoot.dspEnabled)
              }
            }

            Repeater {
              model: panelRoot.displayAudioSinks

              SinkRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
                barForeground: panelRoot.barForeground
                barFontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                cursorActive: panelRoot.cursorActive
                focusSection: panelRoot.focusSection
                selectedIndex: panelRoot.selectedIndex
                sink: panelRoot.sink
                sinkAvailable: panelRoot.sinkAvailable
                isDspSink: panelRoot.isDspSink
                sinkGlyph: panelRoot.sinkGlyph
                nodeLabel: panelRoot.nodeLabel
                selectSink: panelRoot.selectSink
                ensureCursorVisible: panelRoot.ensureCursorVisible
              }
            }
          }

          // ---- Input ----
          PanelSeparator {
            visible: panelRoot.displayAudioSources.length > 0 || !!panelRoot.source
            foreground: panelRoot.barForeground
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: panelRoot.displayAudioSources.length > 0 || !!panelRoot.source

            Item {
              width: parent.width
              implicitHeight: Math.max(microphoneHeader.implicitHeight, microphonePercent.implicitHeight, inputMuteButton.implicitHeight)

              PanelSectionHeader {
                id: microphoneHeader
                text: "INPUT"
                foreground: panelRoot.barForeground
                fontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: microphonePercent
                textFormat: Text.PlainText
                text: panelRoot.inputMuted
                  ? "MUTED"
                  : Math.round((inputSlider.dragging ? inputSlider.liveValue : panelRoot.inputVolume) * 100) + "%"
                color: panelRoot.secondaryForeground
                font.family: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: inputMuteButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              // Input mute is a real action, so it gets its own icon button
              // beside the level, matching the hero output mute control.
              PanelActionButton {
                id: inputMuteButton
                iconText: panelRoot.inputIcon()
                tooltipText: panelRoot.inputMuted ? "Unmute input" : "Mute input"
                foreground: panelRoot.barForeground
                fontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                fontSize: Style.font.title
                size: Style.space(26)
                bordered: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: panelRoot.toggleInputMute()
              }
            }

            CursorSurface {
              id: inputSliderRow
              visible: !!panelRoot.source
              width: parent.width
              height: inputControls.implicitHeight + Style.spacing.controlGap
              hasCursor: panelRoot.cursorActive && panelRoot.focusSection === "input" && panelRoot.selectedIndex === -1
              onHasCursorChanged: if (hasCursor) panelRoot.ensureCursorVisible(inputSliderRow)
              foreground: panelRoot.barForeground
              outline: true

              Item {
                id: inputControls
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                implicitHeight: inputSlider.implicitHeight

                PanelSlider {
                  id: inputSlider
                  bar: panelRoot.bar
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  // Extra trailing headroom so a 100% thumb is not jammed
                  // against the row edge.
                  anchors.rightMargin: Style.space(8)
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: panelRoot.inputVolume
                  opacity: panelRoot.inputMuted ? 0.5 : 1.0
                  enabled: !!panelRoot.source

                  onMoved: function(v) { panelRoot.setInputVolume(v) }
                  onRightClicked: panelRoot.toggleInputMute()
                }

                // Peak meter: a thin line that hugs the track instead of a
                // second, empty slider. It spans the track exactly.
                Rectangle {
                  id: inputMeter
                  anchors.top: inputSlider.verticalCenter
                  anchors.topMargin: Math.round(inputSlider.trackHeight / 2) + Style.space(3)
                  anchors.left: inputSlider.left
                  anchors.right: inputSlider.right
                  anchors.leftMargin: inputSlider.knobSize / 2
                  anchors.rightMargin: inputSlider.knobSize / 2
                  height: Math.max(2, Style.space(3))
                  radius: height / 2
                  color: Util.alpha(panelRoot.barForeground, 0.22)
                  opacity: panelRoot.inputMuted ? 0.35 : 1.0

                  Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, inputPeakMonitor.peak))
                    color: panelRoot.barForeground
                    Behavior on width { NumberAnimation { duration: 70 } }
                  }
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  panelRoot.cursorActive = true
                  panelRoot.focusSection = "input"
                  panelRoot.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: panelRoot.displayAudioSources

              SourceRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
                barForeground: panelRoot.barForeground
                barFontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                cursorActive: panelRoot.cursorActive
                focusSection: panelRoot.focusSection
                selectedIndex: panelRoot.selectedIndex
                source: panelRoot.source
                sourceGlyph: panelRoot.sourceGlyph
                nodeLabel: panelRoot.nodeLabel
                setDefaultSource: panelRoot.setDefaultSource
                ensureCursorVisible: panelRoot.ensureCursorVisible
              }
            }
          }

          // ---- Per-app streams ----
          PanelSeparator {
            visible: panelRoot.displayAudioStreams.length > 0
            foreground: panelRoot.barForeground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: panelRoot.displayAudioStreams.length > 0

            PanelSectionHeader {
              text: "SOURCES"
              foreground: panelRoot.barForeground
              fontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
            }

            Repeater {
              model: panelRoot.displayAudioStreams

              StreamRow {
                required property var modelData
                required property int index
                width: panelColumn.width
                node: modelData
                rowIndex: index
                barForeground: panelRoot.barForeground
                barFontFamily: panelRoot.bar ? panelRoot.bar.fontFamily : Style.fontFamily
                cursorActive: panelRoot.cursorActive
                focusSection: panelRoot.focusSection
                selectedIndex: panelRoot.selectedIndex
                activeMediaPlayer: panelRoot.activeMediaPlayer
                streamRepresentsPlayer: panelRoot.streamRepresentsPlayer
                streamLabel: panelRoot.streamLabel
                ensureCursorVisible: panelRoot.ensureCursorVisible
              }
            }
          }
        }
      }

      // Scroll affordance: fade the last rows into the panel background only
      // while the content actually overflows. Without it the cut-off bottom
      // looks like a layout bug rather than a scrollable list.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(26)
        visible: panelColumn.implicitHeight > scrollArea.height + 1
        gradient: Gradient {
          GradientStop {
            position: 0.0
            color: Util.alpha(panelRoot.bar ? panelRoot.bar.background : Color.background, 0.0)
          }
          GradientStop {
            position: 1.0
            color: panelRoot.bar ? panelRoot.bar.background : Color.background
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
    property var node
    property int rowIndex
    property color barForeground
    property string barFontFamily
    property bool cursorActive
    property string focusSection
    property int selectedIndex
    property var sink
    property var sinkAvailable
    property var isDspSink
    property var sinkGlyph
    property var nodeLabel
    property var selectSink
    property var ensureCursorVisible

    readonly property bool isValidNode: !!node
    readonly property bool isActive: isValidNode && sink && node && sink.id === node.id
    // Availability is advisory only (dimming); the row stays clickable.
    readonly property bool isAvailable: isValidNode && sinkAvailable(node)
    readonly property bool isDsp: isValidNode && isDspSink(node)
    // Active is shown by a trailing check, never by a filled row. The fill is
    // reserved for the keyboard/mouse cursor so the two states cannot be
    // mistaken for each other.
    readonly property string statusText: !isValidNode
      ? ""
      : (isActive ? (isDsp ? "✓ DSP" : "✓")
      : (isAvailable ? "" : "Disconnected"))
    readonly property color statusColor: isActive ? barForeground : panelRoot.secondaryForeground
    hasCursor: cursorActive && focusSection === "output" && selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) ensureCursorVisible(sinkRow)
    current: false
    foreground: barForeground
    fill: hoverFill
    currentFill: selectedFill
    implicitHeight: sinkInner.implicitHeight + Style.spacing.xl
    opacity: isAvailable ? 1.0 : 0.55

    Row {
      id: sinkInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        id: sinkIcon
        textFormat: Text.PlainText
        text: sinkGlyph(sinkRow.node)
        color: barForeground
        font.family: barFontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: sinkName
        textFormat: Text.PlainText
        text: nodeLabel(sinkRow.node)
        color: barForeground
        font.family: barFontFamily
        font.pixelSize: Style.font.body
        font.bold: sinkRow.isActive
        elide: Text.ElideRight
        width: parent.width - sinkIcon.width - sinkStatus.width - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter

        PanelToolTip {
          visible: sinkMouse.containsMouse && sinkName.truncated
          text: sinkName.text
          fontFamily: barFontFamily
        }
      }

      Text {
        id: sinkStatus
        textFormat: Text.PlainText
        text: sinkRow.statusText
        color: sinkRow.statusColor
        font.family: barFontFamily
        font.pixelSize: Style.font.caption
        font.bold: sinkRow.isActive
        width: Style.space(82)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: sinkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        cursorActive = true
        focusSection = "output"
        selectedIndex = sinkRow.rowIndex
      }
      onClicked: selectSink(sinkRow.node)
    }
  }

  // Input device row — sibling of SinkRow for the "input" section.
  component SourceRow: CursorSurface {
    id: sourceRow
    property var node
    property int rowIndex
    property color barForeground
    property string barFontFamily
    property bool cursorActive
    property string focusSection
    property int selectedIndex
    property var source
    property var sourceGlyph
    property var nodeLabel
    required property var setDefaultSource
    property var ensureCursorVisible

    readonly property bool isActive: source && node && source.id === node.id
    hasCursor: cursorActive && focusSection === "input" && selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) ensureCursorVisible(sourceRow)
    current: false
    foreground: barForeground
    fill: hoverFill
    currentFill: selectedFill
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
        id: sourceIcon
        textFormat: Text.PlainText
        text: sourceGlyph(sourceRow.node)
        color: barForeground
        font.family: barFontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: sourceName
        textFormat: Text.PlainText
        text: nodeLabel(sourceRow.node)
        color: barForeground
        font.family: barFontFamily
        font.pixelSize: Style.font.body
        font.bold: sourceRow.isActive
        elide: Text.ElideRight
        width: parent.width - sourceIcon.width - sourceStatus.width - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter

        PanelToolTip {
          visible: sourceMouse.containsMouse && sourceName.truncated
          text: sourceName.text
          fontFamily: barFontFamily
        }
      }

      Text {
        id: sourceStatus
        textFormat: Text.PlainText
        text: sourceRow.isActive ? "✓" : ""
        color: barForeground
        font.family: barFontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        width: Style.space(82)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: sourceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        cursorActive = true
        focusSection = "input"
        selectedIndex = sourceRow.rowIndex
      }
      onClicked: setDefaultSource(sourceRow.node)
    }
  }

  // Per-app stream row — cursor target inside the "streams" section.
  // The stream has its own slider inline, so h/l from the keyboard
  // adjusts THIS stream's volume (not the global output) when the cursor
  // sits on this row. Enter/Space mutes the stream.
  component StreamRow: CursorSurface {
    id: streamRow
    property var node
    property int rowIndex
    property color barForeground
    property string barFontFamily
    property bool cursorActive
    property string focusSection
    property int selectedIndex
    property var activeMediaPlayer
    required property var streamRepresentsPlayer
    required property var streamLabel
    property var ensureCursorVisible

    readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
    readonly property bool streamMuted: node && node.audio ? node.audio.muted : false
    readonly property bool isActive: streamRepresentsPlayer(node, activeMediaPlayer)

    hasCursor: cursorActive && focusSection === "streams" && selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) ensureCursorVisible(streamRow)
    current: isActive
    foreground: barForeground
    fill: hoverFill
    currentFill: selectedFill
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
          text: streamRow.streamMuted ? "\uf026" : "\uf028"
          color: barForeground
          font.family: barFontFamily
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
          id: streamName
          textFormat: Text.PlainText
          text: streamLabel(streamRow.node)
          color: barForeground
          font.family: barFontFamily
          font.pixelSize: Style.font.body
          font.bold: streamRow.isActive
          elide: Text.ElideRight
          width: parent.width - streamMuteIcon.width - streamPct.width - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter

          PanelToolTip {
            visible: streamMouse.containsMouse && streamName.truncated
            text: streamName.text
            fontFamily: barFontFamily
          }
        }

        Text {
          id: streamPct
          textFormat: Text.PlainText
          text: Math.round(streamRow.streamVolume * 100) + "%"
          color: streamRow.streamVolume > 1
            ? panelRoot.overdriveColor
            : Qt.darker(barForeground, 1.2)
          font.family: barFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0
        }
      }

      Item {
        id: streamSliderWrap
        width: parent.width
        implicitHeight: streamSlider.implicitHeight
        readonly property real trackLeft: streamSlider.x + streamSlider.knobSize / 2
        readonly property real trackWidth: Math.max(0, streamSlider.width - streamSlider.knobSize)
        readonly property real thresholdX: trackLeft + trackWidth * (1 / 1.5)
        readonly property real valueX: trackLeft + trackWidth * Math.min(1, streamRow.streamVolume / 1.5)

        PanelSlider {
          id: streamSlider
          bar: panelRoot.bar
          anchors.fill: parent
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

        Rectangle {
          anchors.verticalCenter: streamSlider.verticalCenter
          x: streamSliderWrap.thresholdX
          width: Math.max(0, streamSliderWrap.valueX - streamSliderWrap.thresholdX)
          height: streamSlider.trackHeight
          radius: height / 2
          color: panelRoot.overdriveColor
          opacity: streamRow.streamMuted ? 0.5 : 1.0
          visible: width > 0
        }

        Rectangle {
          anchors.verticalCenter: streamSlider.verticalCenter
          width: Math.max(1, Style.space(2))
          height: streamSlider.trackHeight + Style.space(6)
          radius: 1
          color: panelRoot.secondaryForeground
          opacity: streamRow.streamMuted ? 0.5 : 1.0
          x: streamSliderWrap.thresholdX - width / 2
        }
      }
    }

    MouseArea {
      id: streamMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      propagateComposedEvents: true
      onContainsMouseChanged: if (containsMouse) {
        cursorActive = true
        focusSection = "streams"
        selectedIndex = streamRow.rowIndex
      }
    }
  }
}
