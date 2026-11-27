#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

[[ -f "$HOME/.local/share/../bin/env" ]] && . "$HOME/.local/share/../bin/env"
