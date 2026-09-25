#!/usr/bin/env bash
# Omarchy customization installer.
#
# Copies the selected customization onto this machine. Existing destination
# files are first backed up to ~/backups/omarchy-customization/
# (only if they differ), then overwritten with the repo's files.
#
# Usage:
#   ./install.sh                  # interactive menu: pick a feature type to install
#   ./install.sh --list           # list the available feature types
#   ./install.sh --apply          # install everything
#   ./install.sh --apply <type>   # install only one feature type
#   ./install.sh --revert         # restore the backups taken by --apply
#
# Safe to re-run: it always takes a fresh timestamped backup before writing.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${HOME}/backups/omarchy-customization"
MODE="${1:-}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TS}"

# relative path in repo -> absolute destination -> feature type
declare -a PAIRS=(
  "hypr/hyprland.lua|${HOME}/.config/hypr/hyprland.lua|window"
  "hypr/hyprland.conf|${HOME}/.config/hypr/hyprland.conf|window"
  "hypr/bindings.lua|${HOME}/.config/hypr/bindings.lua|window"
  "hypr/bindings.lua.backup|${HOME}/.config/hypr/bindings.lua.backup|window"
  "hypr/looknfeel.lua|${HOME}/.config/hypr/looknfeel.lua|window"
  "hypr/windows.lua|${HOME}/.config/hypr/windows.lua|window"
  "hypr/monitors.lua|${HOME}/.config/hypr/monitors.lua|window"
  "hypr/autostart.lua|${HOME}/.config/hypr/autostart.lua|window"
  "hypr/input.lua|${HOME}/.config/hypr/input.lua|touchpad"
  "mogtab/config.toml|${HOME}/.config/mogtab/config.toml|apps"
  "bin/mogtab|${HOME}/.local/bin/mogtab|apps"
  "bin/mogtabctl|${HOME}/.local/bin/mogtabctl|apps"
  "bin/omarchy-switch|${HOME}/.local/bin/omarchy-switch|apps"
  "bin/omarchy-display-mode|${HOME}/.local/bin/omarchy-display-mode|apps"
  "bin/omarchy-fullscreen-watch|${HOME}/.local/bin/omarchy-fullscreen-watch|apps"
  "bin/omarchy-emulator-snap|${HOME}/.local/bin/omarchy-emulator-snap|apps"
  "bin/omarchy-emulator|${HOME}/.local/bin/omarchy-emulator|apps"
  "bin/omarchy-audio-output-volume|${HOME}/.local/bin/omarchy-audio-output-volume|apps"
  "bin/omarchy-emulator-mouse|${HOME}/.local/bin/omarchy-emulator-mouse|apps"
  "ghostty/config|${HOME}/.config/ghostty/config|apps"
  "src/pointer-warp.c|${HOME}/.local/src/omarchy-customization/pointer-warp.c|apps"
  "systemd/omarchy-crash-watch.service.d/override.conf|${HOME}/.config/systemd/user/omarchy-crash-watch.service.d/override.conf|apps"
  "bin/omarchy-window-snap|${HOME}/.local/bin/omarchy-window-snap|apps"
  "bin/omarchy-toggle-bar-mode|${HOME}/.local/bin/omarchy-toggle-bar-mode|apps"
  "toggles/single-window-aspect-ratio.lua|${HOME}/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua|apps"
  "omarchy/shell.json|${HOME}/.config/omarchy/shell.json|shell"
  "omarchy/shell.toml|${HOME}/.config/omarchy/shell.toml|shell"
  "omarchy/plugins/bar-auto-hide/manifest.json|${HOME}/.config/omarchy/plugins/bar-auto-hide/manifest.json|shell"
  "omarchy/plugins/bar-auto-hide/Bar.qml|${HOME}/.config/omarchy/plugins/bar-auto-hide/Bar.qml|shell"
  "omarchy/plugins/bar-auto-hide/BarModel.js|${HOME}/.config/omarchy/plugins/bar-auto-hide/BarModel.js|shell"
  "omarchy/plugins/snap-preview/manifest.json|${HOME}/.config/omarchy/plugins/snap-preview/manifest.json|shell"
  "omarchy/plugins/snap-preview/SnapPreview.qml|${HOME}/.config/omarchy/plugins/snap-preview/SnapPreview.qml|shell"
  "omarchy/plugins/com.sandy.taskbar/manifest.json|${HOME}/.config/omarchy/plugins/com.sandy.taskbar/manifest.json|shell"
  "omarchy/plugins/com.sandy.taskbar/TaskbarWidget.qml|${HOME}/.config/omarchy/plugins/com.sandy.taskbar/TaskbarWidget.qml|shell"
  "omarchy/plugins/com.sandy.display/manifest.json|${HOME}/.config/omarchy/plugins/com.sandy.display/manifest.json|shell"
  "omarchy/plugins/com.sandy.display/Panel.qml|${HOME}/.config/omarchy/plugins/com.sandy.display/Panel.qml|shell"
  "omarchy/plugins/com.sandy.display/Model.js|${HOME}/.config/omarchy/plugins/com.sandy.display/Model.js|shell"
  "omarchy/plugins/com.sandy.audio/manifest.json|${HOME}/.config/omarchy/plugins/com.sandy.audio/manifest.json|shell"
  "omarchy/plugins/com.sandy.audio/Panel.qml|${HOME}/.config/omarchy/plugins/com.sandy.audio/Panel.qml|shell"
  "omarchy/plugins/com.sandy.audio/Model.js|${HOME}/.config/omarchy/plugins/com.sandy.audio/Model.js|shell"
  "docs/OMARCHY_KEYBINDINGS_REFERENCE.md|${HOME}/OMARCHY_KEYBINDINGS_REFERENCE.md|docs"
)

# feature type -> human label (menu order)
declare -a TYPE_ORDER=(everything touchpad window shell apps docs)
declare -A TYPE_LABEL=(
  [everything]="Everything (full install)"
  [touchpad]="Reversed touchpad gestures"
  [window]="Hyprland: bindings, Alt-Tab switcher, Super+P display, monitors"
  [shell]="Omarchy shell: display/audio panels, taskbar, bar plugins"
  [apps]="Helper CLIs: omarchy-switch, omarchy-display-mode, toggles"
  [docs]="Documentation"
)

info()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m%s\033[0m\n' "$*"; }

usage() {
  cat <<'EOF'
Usage:
  ./install.sh                  interactive menu: tick feature types
                                (SPACE/fzf-TAB multi-select), then install
  ./install.sh --list           list the available feature types
  ./install.sh --apply          install everything
  ./install.sh --apply <type>   install only one feature type
  ./install.sh --revert         restore the backups taken by --apply
EOF
}

# Print "type|label" lines in menu order.
sorted_types() {
  for t in "${TYPE_ORDER[@]}"; do
    [ -n "${TYPE_LABEL[$t]:-}" ] && printf '%s|%s\n' "$t" "${TYPE_LABEL[$t]}"
  done
}

# Echo the PAIRS lines that belong to a feature type ("everything" = all).
pairs_for() {
  local want="$1"
  local pair rel rest dest type
  for pair in "${PAIRS[@]}"; do
    rel="${pair%%|*}"
    rest="${pair#*|}"
    dest="${rest%%|*}"
    type="${rest#*|}"
    if [ "$want" = "everything" ] || [ "$type" = "$want" ]; then
      printf '%s\n' "$rel|$dest"
    fi
  done
}

# Interactive multi-selection with tickmarks (fzf when available, whiptail
# checklist fallback, numbered prompt as a last resort). Prints one chosen
# type code per line (empty = cancelled).
choose_types() {
  if command -v fzf >/dev/null 2>&1; then
    sorted_types | sed 's/^\([^|]*\)|\(.*\)$/\1:  \2/' |
      fzf --multi --height 40% --border --header \
        'Omarchy customization — TAB to tick features, Enter to install (Esc = cancel)' \
        --prompt '> ' |
      while IFS= read -r line; do
        printf '%s\n' "${line%%:*}"
      done
    return
  fi
  if command -v whiptail >/dev/null 2>&1; then
    local args=() t label
    while IFS='|' read -r t label; do
      [ -n "$t" ] && args+=("$t" "$label" "OFF")
    done < <(sorted_types)
    # checklist prints quoted tags: "apps" "shell" — one per line here.
    whiptail --title "Omarchy customization" \
      --checklist "Tick features with SPACE, confirm with ENTER (Esc = cancel):" \
      20 72 6 "${args[@]}" 3>&1 1>&2 2>&3 | tr -s '[:space:]' '\n' | tr -d '"'
    return
  fi
  # Last resort: prompts go to stderr so only type codes reach stdout.
  info "Available feature types:" >&2
  local i t label
  i=0
  while IFS='|' read -r t label; do
    [ -n "$t" ] || continue
    i=$((i + 1))
    printf '  %d) %s\n' "$i" "$label" >&2
    eval "OPT_${i}=$t"
  done < <(sorted_types)
  printf 'Pick numbers separated by spaces (e.g. 1 3 4), "all", or empty to cancel: ' >&2
  local n sel
  read -r n
  if [ "$n" = "all" ]; then
    printf '%s\n' "everything"
    return
  fi
  for sel in $n; do
    [ -n "$(eval "echo \${OPT_${sel}:-}")" ] && eval "echo \${OPT_${sel}}"
  done
}

apply() {
  # Reads "rel|dest" lines on stdin; backs up and installs each.
  local pairs=() line
  while IFS= read -r line; do
    [ -n "$line" ] && pairs+=("$line")
  done
  if [ "${#pairs[@]}" -eq 0 ]; then
    warn "No files for this feature type. Nothing to install."
    return
  fi

  info "Backing up existing files to: $BACKUP_DIR"
  local changed=0 pair rel dest src backupless
  for pair in "${pairs[@]}"; do
    rel="${pair%%|*}"
    dest="${pair#*|}"
    src="$SCRIPT_DIR/$rel"
    [ -f "$src" ] || continue
    backupless=false
    if [ -f "$dest" ]; then
      if ! cmp -s "$src" "$dest"; then
        mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
        cp "$dest" "$BACKUP_DIR/$rel"
        backupless=true
      fi
    else
      backupless=true
    fi
    if [ "$backupless" = true ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      ok "Installed $dest"
      changed=$((changed + 1))
    else
      info "Already up to date: $dest"
    fi
  done
  chmod +x "${HOME}/.local/bin/mogtab" "${HOME}/.local/bin/mogtabctl" \
    "${HOME}/.local/bin/omarchy-window-snap" "${HOME}/.local/bin/omarchy-toggle-bar-mode" \
    "${HOME}/.local/bin/omarchy-switch" "${HOME}/.local/bin/omarchy-display-mode" \
    "${HOME}/.local/bin/omarchy-fullscreen-watch" "${HOME}/.local/bin/omarchy-emulator-snap" \
    "${HOME}/.local/bin/omarchy-emulator" \
    "${HOME}/.local/bin/omarchy-emulator-mouse" \
    "${HOME}/.local/bin/omarchy-audio-output-volume" 2>/dev/null || true
  if [ "$changed" -gt 0 ]; then
    info "Reloading Hyprland config..."
    hyprctl reload >/dev/null 2>&1 || true
    # restart the Alt+Tab/Super+Tab switcher (mogtab) if it is running
    if pgrep -f "mogtab run" >/dev/null 2>&1; then
      pkill -f "mogtab run" 2>/dev/null || true
      setsid "${HOME}/.local/bin/mogtab" run &>/dev/null &
    fi
    # pick up a changed crash-watch drop-in (ignore list) if present
    if [ -f "${HOME}/.config/systemd/user/omarchy-crash-watch.service.d/override.conf" ]; then
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      systemctl --user try-restart omarchy-crash-watch.service >/dev/null 2>&1 || true
    fi
  fi
  ok "Done. $changed file(s) installed."
}

revert() {
  info "Reverting to files from last Omarchy customization backup..."
  [ -d "$BACKUP_ROOT" ] || { warn "No backups found at $BACKUP_ROOT"; exit 0; }
  latest="$(ls -1t "$BACKUP_ROOT" | head -n1)"
  [ -n "$latest" ] || { warn "No backups found under $BACKUP_ROOT"; exit 0; }
  local dir="$BACKUP_ROOT/$latest"
  info "Using backup: $dir"
  local pair rel dest rest
  for pair in "${PAIRS[@]}"; do
    rel="${pair%%|*}"
    rest="${pair#*|}"
    dest="${rest%%|*}"
    if [ -f "$dir/$rel" ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$dir/$rel" "$dest"
      ok "Restored $dest"
    fi
  done
}

case "${MODE}" in
  ""|"--menu")
    mapfile -t CHOSEN < <(choose_types)
    if [ "${#CHOSEN[@]}" -eq 0 ]; then
      info "Cancelled."
      exit 0
    fi
    names=()
    for t in "${CHOSEN[@]}"; do
      if [ -z "${TYPE_LABEL[$t]:-}" ]; then
        warn "Unknown feature type: $t"
        exit 1
      fi
      names+=("${TYPE_LABEL[$t]}")
    done
    info "Installing feature(s): $(IFS=', '; echo "${names[*]}")"
    { for t in "${CHOSEN[@]}"; do pairs_for "$t"; done; } | apply
    ;;
  --list)
    info "Available feature types:"
    while IFS='|' read -r t label; do
      [ -n "$t" ] && printf '  %-10s %s\n' "$t" "$label"
    done < <(sorted_types)
    ;;
  --apply)
    t="${2:-everything}"
    if [ -z "${TYPE_LABEL[$t]:-}" ]; then
      warn "Unknown feature type: $t"
      usage
      exit 1
    fi
    info "Installing feature: ${TYPE_LABEL[$t]}"
    pairs_for "$t" | apply
    ;;
  --revert)
    revert
    ;;
  -h|--help)
    usage
    ;;
  *)
    warn "Unknown option: $MODE"
    usage
    exit 1
    ;;
esac