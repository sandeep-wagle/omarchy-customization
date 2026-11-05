# Omarchy environment (OMARCHY_PATH + PATH), needed even for non-interactive shells
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap

# If not running interactively, don't do anything else (leave this above the rc source)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

# --- Flutter / Android SDK (added by opencode 2026-09-18) ---
export JAVA_HOME="$HOME/.local/share/mise/installs/java/17.0.2"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$HOME/Development/sdk/flutter/bin:$HOME/Android/Sdk/cmdline-tools/latest/bin:$HOME/Android/Sdk/platform-tools:$PATH"
export LIBVA_DRIVER_NAME=iHD
export ANDROID_AVD_HOME="$HOME/.config/.android/avd"
. "$HOME/.cargo/env"

# Only successful commands stay in history: if the last command failed
# (typo like `fluter run`, bad flags, ...), drop it so autosuggestions never
# offer broken commands again. Exit status is preserved for the prompt.
__forget_failed_command() {
  local code=$?
  if (( code != 0 )); then
    history -d "$(HISTTIMEFORMAT= history 1 | awk '{print $1}')" 2>/dev/null
  fi
  return $code
}
PROMPT_COMMAND="__forget_failed_command; __dirhist_sync${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# Per-directory history: suggestions follow the directory you're in.
# `flutter run` typed in ~/project is suggested there, not in ~.
# Each directory gets its own history file (named by path hash) under
# ~/.local/share/bash-dirhist; switching directories swaps the in-memory
# list that ble.sh suggests from. Nothing is ever deleted except by the
# failed-command filter above.
__dirhist_dir="${BASH_DIRHIST_DIR:-$HOME/.local/share/bash-dirhist}"
__dirhist_last=""
__dirhist_sync() {
  [[ $PWD == "$__dirhist_last" ]] && return 0
  mkdir -p "$__dirhist_dir" 2>/dev/null
  if [[ -n $__dirhist_last ]]; then
    local old_hash
    old_hash=$(printf '%s' "$__dirhist_last" | sha1sum | cut -d' ' -f1)
    history -a "$__dirhist_dir/$old_hash" 2>/dev/null
  fi
  local new_hash
  new_hash=$(printf '%s' "$PWD" | sha1sum | cut -d' ' -f1)
  echo "$PWD" > "$__dirhist_dir/$new_hash.path" 2>/dev/null
  history -c
  history -r "$__dirhist_dir/$new_hash" 2>/dev/null
  __dirhist_last=$PWD
}
__dirhist_exit() {
  [[ -n $__dirhist_last ]] || return 0
  local h
  h=$(printf '%s' "$__dirhist_last" | sha1sum | cut -d' ' -f1)
  history -a "$__dirhist_dir/$h" 2>/dev/null
}
trap '__dirhist_exit' EXIT

# Fish-like autosuggestions + syntax highlighting (ble.sh).
# Must stay last: it hooks the command line after everything else loads.
# Keys: Right-arrow / End = accept suggestion, Alt+Right = accept one word.
[[ $- == *i* ]] && source "$HOME/.local/share/blesh/out/ble.sh"

# ble.sh: make Enter/Return execute commands normally, including multiline input.
ble-bind -f 'C-m' accept-line
ble-bind -f 'RET' accept-line


alias vm="ssh -t sandy@192.168.122.100 bash --login"

alias vm='ssh -t sandy@192.168.122.100 bash --login'

alias vm='ssh -t sandy@192.168.122.100 bash --login'

. "$HOME/.local/share/../bin/env"
export PATH="$(npm prefix -g)/bin:$PATH"

# Android SDK
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
