#!/usr/bin/env bash
# End-to-end installer smoke test in a throwaway HOME.
#
# Proves that `install.sh --apply everything` installs the tracked files,
# that `--verify` reports no drift, and that `--revert` restores a file the
# installer backed up. The real session is never touched: hyprctl, systemctl,
# pgrep and pkill are stubbed, and the session bus is unset.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

STUBS="$TMP/stubs"
mkdir -p "$STUBS"
for cmd in hyprctl systemctl pkill; do
  printf '#!/bin/sh\nexit 0\n' >"$STUBS/$cmd"
  chmod +x "$STUBS/$cmd"
done
# Nothing is running in the sandbox, so the installer must not try to restart
# mogtab (pgrep success would start it against the real session).
printf '#!/bin/sh\nexit 1\n' >"$STUBS/pgrep"
chmod +x "$STUBS/pgrep"
export PATH="$STUBS:$PATH"
unset DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR 2>/dev/null || true

fail() {
  printf 'SMOKE FAIL: %s\n' "$*" >&2
  exit 1
}

printf 'sentinel-original\n' >"$HOME/.bashrc"

"$ROOT/install.sh" --list >"$TMP/list.txt"
grep -q 'everything' "$TMP/list.txt" || fail "--list does not show the everything feature"

"$ROOT/install.sh" --apply everything >"$TMP/apply.log" 2>&1 ||
  { cat "$TMP/apply.log" >&2; fail "install.sh --apply exited non-zero"; }

"$ROOT/install.sh" --verify >"$TMP/verify.log" 2>&1 ||
  { cat "$TMP/verify.log" >&2; fail "install.sh --verify reported drift after install"; }

[ -x "$HOME/.local/bin/omarchy-switch" ] || fail "omarchy-switch was not installed executable"
[ -f "$HOME/.config/hypr/hyprland.lua" ] || fail "hyprland.lua was not installed"
[ -f "$HOME/.config/omarchy/shell.json" ] || fail "shell.json was not installed"
[ -f "$HOME/.config/ghostty/config" ] || fail "ghostty config was not installed"

# Regression guard: the square single-window toggle used to be installed and
# left ~420 px bars either side of a lone window on a 1920x1080 panel.
if [ -e "$HOME/.local/state/omarchy/toggles/hypr/single-window-aspect-ratio.lua" ]; then
  fail "single-window-aspect-ratio toggle was installed; a lone window would not fill the screen"
fi

# Re-running must be safe (idempotent) and leave no drift.
"$ROOT/install.sh" --apply everything >"$TMP/apply2.log" 2>&1 ||
  { cat "$TMP/apply2.log" >&2; fail "second install.sh --apply exited non-zero"; }
"$ROOT/install.sh" --verify >/dev/null 2>&1 || fail "drift after re-running the installer"

# A pre-existing file must be backed up and restored by --revert.
compgen -G "$HOME/backups/omarchy-customization/*/dotfiles/.bashrc" >/dev/null ||
  fail "installer did not back up the pre-existing .bashrc"

"$ROOT/install.sh" --revert >"$TMP/revert.log" 2>&1 ||
  { cat "$TMP/revert.log" >&2; fail "install.sh --revert exited non-zero"; }

grep -qx 'sentinel-original' "$HOME/.bashrc" ||
  fail "--revert did not restore the backed-up .bashrc"

echo "Installer smoke test passed (apply, verify, idempotent re-apply, revert)."
