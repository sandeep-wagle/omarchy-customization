import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Windows/Ubuntu-style taskbar over the REAL Hyprland window model.
//
// Data source:  Hyprland.focusedWorkspace.toplevels  (the live, event-driven
//               per-workspace window model). No polling, no local registry —
//               the compositor stays the source of truth, so closing/moving/
//               workspace changes and focus changes all flow through here.
//
// Each model entry is an exact Hyprland client (stable id = its address).
//   - left-click   -> focus that EXISTING window (switches workspace if the
//                     window is elsewhere; restores minimized windows; never
//                     launches another instance) and raises it to the top
//   - middle/right -> send a graceful close request (window stays alive until
//                     the app agrees; we never kill the process ourselves)
//   - minimized windows are kept in the list, dimmed, and restored on click.
//
// Rendering rule (keeps the bar width bounded so windows can never overlap
// the clock/tray/etc.):
//   - focused item : icon + title text, title truncated with an ellipsis past
//                    `expandedItemLabel` px (default 160 -> ~200px chip max)
//   - every OTHER (inactive) item: icon only, fixed ~30px chip
//   - total width ~ expandedW + collapsedW * (count - 1), independent of title
//     length; the expanded/collapsed switch is bound straight to the model's
//     `activated` state so it tracks focus changes live (click, Alt-Tab, etc.)

BarWidget {
  id: root
  moduleName: "com.sandy.taskbar"

  // Settings injected by the bar slot for this entry (see Bar.qml injectProps).
  // Tunable per bar entry: { "com.sandy.taskbar": { "maxWidth": 200 } }.
  property var settings: ({})
  // Cap (px) for the label area of the expanded/focused item. The chip size
  // forces an ellipsis instead of letting a long title shove into
  // neighboring bar widgets.
  property real expandedItemLabel: {
    var n = Number(settings && settings.maxWidth)
    return isFinite(n) && n > 0 ? n : 160
  }

  // --- freedesktop app-icon resolution ------------------------------------
  // A window chip must show the app's real icon, resolved like the launcher
  // does: Hyprland's `class` == Wayland app_id / X11 wm_class is matched to the
  // app's .desktop entry (`<app_id>.desktop` under the XDG application dirs,
  // including flatpak exports), and the entry's `Icon=` value drives the icon
  // theme lookup. This closes the app_id-vs-icon mismatch that breaks bare
  // class-name lookups — brave's class is "brave-browser" but its icon is
  // "brave-desktop", and only the desktop entry knows that. A fresh-disk
  // app/device icon index is the second fallback (icons Qt's cached theme
  // search misses because they were installed after this process started, or
  // live outside a theme). Only the final step is the generic file icon.
  property var desktopIconByApp: ({})
  property var iconIndex: ({})
  property var pendingDesktopIconByApp: ({})
  property var pendingIconIndex: ({})

  function iconScanCommand() {
    // Section 1: "<app_id>\t<Icon-value>" per desktop entry (first Icon= wins,
    // i.e. the main [Desktop Entry] group). Section 2: every icon file under
    // the XDG icon dirs' apps/ + devices/ subtrees plus /usr/share/pixmaps,
    // emitting paths only (SVGs before PNGs so the parser keeps scalable art).
    return [
      'dirs="$HOME/.local/share/applications";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/applications"; done; unset IFS;',
      'for extra in "$HOME/.local/share/flatpak/exports/share/applications" "/var/lib/flatpak/exports/share/applications"; do',
      '  [ -d "$extra" ] && dirs="$dirs $extra";',
      'done;',
      'for f in $(find $dirs -maxdepth 1 -name "*.desktop" 2>/dev/null); do',
      '  id=${f##*/}; id=${id%.desktop};',
      '  icon_v=$(awk -F= \'$1=="Icon"{print $2; exit}\' "$f");',
      '  [ -n "$icon_v" ] && echo -e "d\\t$id\\t$icon_v";',
      'done;',
      'idirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do idirs="$idirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $idirs; do',
      '    [ -d "$base" ] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function indexScanLine(line) {
    var parts = String(line || "").split("\t")
    if (parts[0] === "d" && parts.length >= 3) {
      if (parts[1].length > 0 && root.pendingDesktopIconByApp[parts[1]] === undefined)
        root.pendingDesktopIconByApp[parts[1]] = parts[2]
      return
    }
    var value = String(parts[0] || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  Process {
    id: iconScan
    command: ["bash", "-c", root.iconScanCommand()]
    stdout: SplitParser { onRead: function(line) { root.indexScanLine(line) } }
    onStarted: { root.pendingDesktopIconByApp = ({}); root.pendingIconIndex = ({}) }
    // Swapping the maps re-evaluates every resolveIcon() binding, so icons of
    // already-mapped windows refresh as soon as the scan completes.
    onExited: {
      root.desktopIconByApp = root.pendingDesktopIconByApp
      root.iconIndex = root.pendingIconIndex
    }
  }

  function resolveIcon(appId) {
    var value = String(appId || "").trim()
    if (value.length === 0) return ""
    // Icon name from the .desktop entry (falls back to the app_id itself).
    var name = String(root.desktopIconByApp[value] || value || "")
    if (name.length === 0) return ""
    if (name.indexOf("file://") === 0 || name.indexOf("image://") === 0) return name
    if (name.charAt(0) === "/") return Util.fileUrl(name)
    // Prefer an explicit themed hit (returns the image://icon/ URI when the
    // current theme knows the name); otherwise hit the fresh-disk index for a
    // real file, and only then hand the name to Qt's full icon chain (which
    // also tries the hicolor fallback theme) or its built-in placeholder.
    var themed = Quickshell.iconPath(name, true)
    if (themed.length > 0) return themed
    var found = root.iconIndex[name] || root.iconIndex[value]
    if (found) return Util.fileUrl(found)
    return "image://icon/" + name
  }

  // Build the hyprctl command that focuses the exact Hyprland client, then
  // raises it above floating peers. Two independent dispatches chained at the
  // shell level (each Lua payload is quoted on its own so the `&&` stays
  // outside any argument).
  // NOTE: the QS window address is bare hex (e.g. "55a7..."), while the
  // compositor selector needs the "address:0x" prefix. Omitting "0x" makes
  // Hyprland report "window not found" and the click silently does nothing.
  function focusCommand(address) {
    if (!address) return ""
    var focusArg = Util.shellQuote('hl.dsp.focus({ window = "address:0x' + address + '" })')
    var raiseArg = Util.shellQuote('hl.dsp.window.alter_zorder({ window = "address:0x' + address + '", mode = "top" })')
    return "hyprctl dispatch " + focusArg + " && hyprctl dispatch " + raiseArg
  }

  function closeCommand(address) {
    if (!address) return ""
    return "hyprctl dispatch " + Util.shellQuote(
      'hl.dsp.window.close({ window = "address:0x' + address + '" })')
  }

  readonly property var ws: Hyprland.focusedWorkspace
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // --- startup focus seed ------------------------------------------------
  // Quickshell.populates `Hyprland.activeToplevel` only when focus *changes*
  // after this widget loads; at boot it's still null, so nothing would expand
  // until the first click/Alt-Tab. Ask the compositor once for the current
  // focused client and use THAT as the focused signal until the live
  // activeToplevel (or the model's `activated`) starts tracking changes.
  // One-shot query: not polling, and once `activeViaHypr` turns true the
  // startup address is completely ignored.
  property string startupActiveAddress: ""
  readonly property bool activeViaHypr: !!Hyprland.activeToplevel

  function applyActiveWindowAddress(raw) {
    try {
      var d = JSON.parse(String(raw || ""))
      var addr = String(d.address || "")
      if (addr.indexOf("0x") === 0) root.startupActiveAddress = addr
    } catch (e) {}
  }

  property Process activeWindowProbe: Process {
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyActiveWindowAddress(text)
    }
  }

  Component.onCompleted: {
    root.activeWindowProbe.running = true
    iconScan.running = true
  }

  implicitWidth: rowList.implicitWidth + trailingGap
  implicitHeight: rowList.implicitHeight

  // The focused workspace's toplevel model drives the Repeater directly, so
  // entries appear/disappear reactively as windows are mapped/unmapped, the
  // active workspace switches, titles change, etc. — no polling needed.
  RowLayout {
    id: rowList
    anchors.fill: parent
    spacing: root.vertical ? 0 : Style.space(1)
    layoutDirection: Qt.LeftToRight

    Repeater {
      id: winRepeater
      model: root.ws ? root.ws.toplevels : null

      delegate: Item {
        id: entry
        required property var modelData

        readonly property var toplevel: modelData || null
        readonly property string title: toplevel ? (toplevel.title || "") : ""
        readonly property bool hasTitle: title !== ""
        readonly property string appClass: toplevel && toplevel.lastIpcObject
          ? String(toplevel.lastIpcObject.class || "") : ""
        readonly property string address: toplevel ? String(toplevel.address || "") : ""
        // The omarchy-switch overlay is a real focused-workspace client, but it
        // is a transient picker and must never appear in the bar. Filtering it
        // to `valid = false` renders a zero-width item that consumes no layout
        // space (same treatment as an invalid entry), so no chip appears.
        readonly property bool isSwitcher: appClass === "omarchy.switch"
        // Every model entry is a real client, so a window renders (icon at
        // minimum) as soon as it has a usable address. A title is only needed
        // for the ACTIVE item's label, never for showing the icon — this keeps
        // all windows (active or not) visible in the bar.
        readonly property bool valid: address !== "" && !isSwitcher
        // `hidden` in this model means "intentionally minimized", NOT "on
        // another workspace": the model only ever lists the focused workspace,
        // so a listed window is either visible or minimized.
        readonly property bool isMinimized: toplevel && toplevel.lastIpcObject
          ? (toplevel.lastIpcObject.hidden === true) : false
        // The one authoritative "focused" signal is identity with the
        // compositor's active toplevel. `toplevel.activated` proved unreliable
        // in this Quickshell/Hyprland build (it stayed false even for the
        // focused window right after load, so no item would expand);
        // `activeToplevel` tracks focus changes instead. Both are only
        // populated on the first focus *change*, so until then we fall back to
        // the compositor's answer captured once at startup
        // (`startupActiveAddress`). `activated` is kept as a secondary
        // live fallback so a stale startup address can never hold focus.
        readonly property bool isActive: toplevel ? (
          root.activeViaHypr
            ? (toplevel === Hyprland.activeToplevel || toplevel.activated === true)
            : (("0x" + entry.address) === root.startupActiveAddress)
        ) : false
        readonly property real iconW: appIcon.width

        // --- rendering rule -------------------------------------------------
        // Only the focused item expands (icon + capped title); every other
        // item is a fixed-size icon-only chip, so the whole taskbar stays
        // bounded (expandedW + collapsedW * inactiveCount + gaps) no matter
        // how long any window's title is. Expanding is bound straight to the
        // compositor's active-toplevel state, so focus changes (click, Alt-Tab,
        // Super+Ctrl+Arrow) reflow items live with no polling or redraw.
        readonly property bool expanded: isActive

        readonly property real collapsedW: Style.space(6) + iconW + Style.space(10)
        readonly property real expandedW:
          Style.space(6) + iconW + Style.space(5) + root.expandedItemLabel + Style.space(8)

        implicitWidth: !valid ? 0 : (expanded ? expandedW : collapsedW)
        implicitHeight: root.barSize

          Behavior on implicitWidth {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }

          opacity: entry.isMinimized ? 0.55 : 1.0

          Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
          }

          Rectangle {
          id: pill
          anchors.fill: parent
          color: entry.isActive
            ? Style.selectedFill
            : (mouse.containsMouse ? Style.hoverFill : Style.normalFill)

          Behavior on color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
          }
        }

        // Running indicator: a small underline under EVERY window chip so the
        // bar always shows every window, no matter how dark its app icon is
        // (an icon glyph by itself can be near-invisible on the dark bar —
        // e.g. this is exactly why some chips looked like they vanished). The
        // active chip uses the accent color and the indicator spans the whole
        // expanded chip; inactive chips get a dim foreground band under just
        // their icon.
        Rectangle {
          id: indicator
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(3)
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          height: 3
          radius: 1.5
          color: entry.isActive
            ? (root.bar && root.bar.barAccent ? root.bar.barAccent : Color.accent)
            : Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.5)
          visible: entry.valid

          Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
          }
        }

        Image {
          id: appIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.icon
          height: Style.font.icon
          sourceSize.width: Style.font.icon * 2
          sourceSize.height: Style.font.icon * 2
          source: root.resolveIcon(entry.appClass)
          visible: entry.valid
        }

        Text {
          id: label
          anchors.left: appIcon.right
          anchors.leftMargin: entry.iconW > 0 ? Style.space(5) : 0
          anchors.verticalCenter: parent.verticalCenter
          width: root.expandedItemLabel
          visible: entry.expanded && entry.hasTitle
          text: entry.title
          color: entry.isActive
            ? (root.bar ? root.bar.barForeground : Color.foreground)
            : Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.85)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignLeft
          verticalAlignment: Text.AlignVCenter
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor

          onClicked: function(mouseEvent) {
            if (!entry.toplevel || !entry.address || !root.bar) return
            if (mouseEvent.button === Qt.LeftButton) {
              // Already-focused item: no-op. Re-dispatching focus to the active
              // window makes Hyprland 0.56 answer "window not found" anyway, and
              // a no-op is the specified repeated-click behavior (never relaunch).
              if (entry.isActive) return
              root.bar.run(root.focusCommand(entry.address))
            } else {
              root.bar.run(root.closeCommand(entry.address))
            }
          }
          onEntered: if (root.bar) root.bar.showTooltip(root, entry.title)
          onExited: if (root.bar) root.bar.hideTooltip(root)
        }
      }
    }
  }
}