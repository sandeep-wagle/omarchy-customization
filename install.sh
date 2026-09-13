#!/usr/bin/env bash
# Omarchy customization installer.
#
# Copies every customization file in this folder onto the current machine.
# Existing destination files are first backed up to ~/backups/omarchy-customization/
# (only if they differ), then overwritten with these files.
#
# Usage:
#   ./install.sh            # dry run: show what would change
#   ./install.sh --apply    # actually back up + install
#   ./install.sh --revert   # restore the backups taken by --apply
#
# Safe to re-run: it always takes a fresh timestamped backup before writing.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${HOME}/backups/omarchy-customization"
MODE="${1:-dry}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TS}"

# relative path in repo -> absolute destination
declare -a PAIRS=(
  "hypr/hyprland.lua|${HOME}/.config/hypr/hyprland.lua"
  "hypr/hyprland.conf|${HOME}/.config/hypr/hyprland.conf"
  "hypr/bindings.lua|${HOME}/.config/hypr/bindings.lua"
  "hypr/bindings.lua.backup|${HOME}/.config/hypr/bindings.lua.backup"
  "hypr/looknfeel.lua|${HOME}/.config/hypr/looknfeel.lua"
  "hypr/windows.lua|${HOME}/.config/hypr/windows.lua"
  "hypr/monitors.lua|${HOME}/.config/hypr/monitors.lua"
  "hypr/autostart.lua|${HOME}/.config/hypr/autostart.lua"
  "mogtab/config.toml|${HOME}/.config/mogtab/config.toml"
  "bin/mogtab|${HOME}/.local/bin/mogtab"
  "bin/mogtabctl|${HOME}/.local/bin/mogtabctl"
  "bin/omarchy-window-snap|${HOME}/.local/bin/omarchy-window-snap"
  "bin/omarchy-toggle-bar-mode|${HOME}/.local/bin/omarchy-toggle-bar-mode"
  "omarchy/shell.json|${HOME}/.config/omarchy/shell.json"
  "omarchy/shell.toml|${HOME}/.config/omarchy/shell.toml"
  "omarchy/plugins/bar-auto-hide/manifest.json|${HOME}/.config/omarchy/plugins/bar-auto-hide/manifest.json"
  "omarchy/plugins/bar-auto-hide/Bar.qml|${HOME}/.config/omarchy/plugins/bar-auto-hide/Bar.qml"
  "omarchy/plugins/bar-auto-hide/BarModel.js|${HOME}/.config/omarchy/plugins/bar-auto-hide/BarModel.js"
  "omarchy/plugins/snap-preview/manifest.json|${HOME}/.config/omarchy/plugins/snap-preview/manifest.json"
  "omarchy/plugins/snap-preview/SnapPreview.qml|${HOME}/.config/omarchy/plugins/snap-preview/SnapPreview.qml"
  "omarchy/plugins/com.sandy.taskbar/manifest.json|${HOME}/.config/omarchy/plugins/com.sandy.taskbar/manifest.json"
  "omarchy/plugins/com.sandy.taskbar/TaskbarWidget.qml|${HOME}/.config/omarchy/plugins/com.sandy.taskbar/TaskbarWidget.qml"
  "toggles/single-window-aspect-ratio.lua|${HOME}/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua"
  "docs/OMARCHY_KEYBINDINGS_REFERENCE.md|${HOME}/OMARCHY_KEYBINDINGS_REFERENCE.md"
)

# map: destination -> relative path (mirror of PAIRS, for --revert)
declare -A DEST_TO_REL
seen=""
for pair in "${PAIRS[@]}"; do
  rel="${pair%%|*}"
  dest="${pair#*|}"
  DEST_TO_REL["$dest"]="$rel"
done

info()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m%s\033[0m\n' "$*"; }

revert() {
  info "Reverting to files from last Omarchy customization backup..."
  [ -d "$BACKUP_ROOT" ] || { warn "No backups found at $BACKUP_ROOT"; exit 0; }
  latest="$(ls -1t "$BACKUP_ROOT" | head -n1)"
  [ -n "$latest" ] || { warn "No backups found under $BACKUP_ROOT"; exit 0; }
  local dir="$BACKUP_ROOT/$latest"
  info "Using backup: $dir"
  for dest in "${!DEST_TO_REL[@]}"; do
    rel="${DEST_TO_REL[$dest]}"
    bak="$dir/$rel"
    if [ -f "$bak" ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$bak" "$dest"
      ok "Restored $dest"
    fi
  done
}

apply() {
  info "Backing up existing files to: $BACKUP_DIR"
  local changed=0
  for pair in "${PAIRS[@]}"; do
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
  chmod +x "${HOME}/.local/bin/mogtab" "${HOME}/.local/bin/mogtabctl" "${HOME}/.local/bin/omarchy-window-snap" "${HOME}/.local/bin/omarchy-toggle-bar-mode"
  if [ "$changed" -gt 0 ]; then
    info "Reloading Hyprland config..."
    hyprctl reload >/dev/null 2>&1 || true
    # restart the Alt+Tab/Super+Tab switcher if it is running
    if pgrep -f "mogtab run" >/dev/null 2>&1; then
      pkill -f "mogtab run" 2>/dev/null || true
      setsid "${HOME}/.local/bin/mogtab" run &>/dev/null &
    fi
  fi
  ok "Done. $changed file(s) installed."
}

case "$MODE" in
  --apply) apply ;;
  --revert) revert ;;
  *) info "Dry run — listing files that would change (use --apply to install):"
       for pair in "${PAIRS[@]}"; do
         rel="${pair%%|*}"
         dest="${pair#*|}"
         src="$SCRIPT_DIR/$rel"
         [ -f "$src" ] || continue
         if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
           info "   [unchanged] $dest"
         else
           info "   [install]   $dest"
         fi
       done ;;
esac