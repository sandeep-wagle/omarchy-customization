# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
bindkey -e
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/home/sandy/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall

# --- Zed editor helper (binary is zeditor) ---
alias zed=zeditor
alias zsw='zeditor ~/.local/bin/omarchy-switch'   # switcher UI file
alias zoc='zeditor ~/omarchy-customization'       # customization project
alias zd='zeditor ~/Development'                  # dev workspace

# --- Flutter / Android SDK (added by opencode 2026-09-18) ---
export JAVA_HOME="$HOME/.local/share/mise/installs/java/17.0.2"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$HOME/Development/sdk/flutter/bin:$HOME/Android/Sdk/cmdline-tools/latest/bin:$HOME/Android/Sdk/platform-tools:$PATH"
export ANDROID_AVD_HOME="$HOME/.config/.android/avd"

# =============================================================================
# Android Pixel 10 Pro Emulator
# =============================================================================

pixel() {
    "$HOME/Android/Sdk/emulator/emulator" \
        -avd Pixel_10_Pro \
        -no-snapshot \
        -gpu host
}

pixelv() {
    local log="$HOME/pixel10-host-$(date +%Y%m%d-%H%M%S).log"

    echo "Starting Pixel_10_Pro in verbose mode..."
    echo "Log: $log"
    echo

    "$HOME/Android/Sdk/emulator/emulator" \
        -avd Pixel_10_Pro \
        -no-snapshot \
        -gpu host \
        -verbose 2>&1 | tee "$log"
}


# =============================================================================
# Android Pixel 10 Pro Emulator
# =============================================================================

pixel() {
    "$HOME/Android/Sdk/emulator/emulator" \
        -avd Pixel_10_Pro \
        -no-snapshot \
        -gpu host
}

pixelv() {
    local log="$HOME/pixel10-host-$(date +%Y%m%d-%H%M%S).log"

    echo "Starting Pixel_10_Pro in verbose mode..."
    echo "Log: $log"
    echo

    "$HOME/Android/Sdk/emulator/emulator" \
        -avd Pixel_10_Pro \
        -no-snapshot \
        -gpu host \
        -verbose 2>&1 | tee "$log"
}


# =============================================================================
# OVERRIDE: Android Pixel 10 Pro
# =============================================================================

pixel() {
    "$HOME/Android/Sdk/emulator/emulator" \
        -avd Pixel_10_Pro \
        -no-snapshot \
        -gpu host
}

pixelv() {
    local log="$HOME/pixel10-host-$(date +%Y%m%d-%H%M%S).log"

    echo "Starting Pixel_10_Pro in verbose mode..."
    echo "Log: $log"
    echo

    "$HOME/Android/Sdk/emulator/emulator" \
        -avd Pixel_10_Pro \
        -no-snapshot \
        -gpu host \
        -verbose 2>&1 | tee "$log"
}

alias vm="ssh -t sandy@192.168.122.100 bash --login"

. "$HOME/.local/share/../bin/env"
