#!/usr/bin/env bash
# Terminal backend: tab title, background color, desktop notifications, bell.
# Uses native terminal escape sequences. Wraps in tmux passthrough when needed.

set -euo pipefail

# ---------------------------------------------------------------------------
# Terminal detection
# ---------------------------------------------------------------------------
TERMINAL_TYPE="unknown"
IN_TMUX=false

detect_terminal() {
    if [ -n "${TMUX:-}" ]; then
        IN_TMUX=true
    fi

    if [ -n "${KITTY_PID:-}" ]; then
        TERMINAL_TYPE="kitty"
    elif [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
        TERMINAL_TYPE="iterm2"
    elif [ "${TERM_PROGRAM:-}" = "WezTerm" ]; then
        TERMINAL_TYPE="wezterm"
    elif [ "${TERM_PROGRAM:-}" = "ghostty" ]; then
        TERMINAL_TYPE="ghostty"
    elif [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]; then
        TERMINAL_TYPE="apple_terminal"
    elif [ -n "${WT_SESSION:-}" ]; then
        TERMINAL_TYPE="windows_terminal"
    elif [ -n "${VTE_VERSION:-}" ]; then
        TERMINAL_TYPE="vte"
    elif [ -n "${ALACRITTY_SOCKET:-}" ]; then
        TERMINAL_TYPE="alacritty"
    fi
}

# ---------------------------------------------------------------------------
# Escape sequence emission
# ---------------------------------------------------------------------------
emit() {
    local seq="$1"
    if [ "$IN_TMUX" = true ]; then
        local wrapped
        wrapped=$(printf '%s' "$seq" | sed 's/\x1b/\x1b\x1b/g')
        printf '\ePtmux;%s\e\\' "$wrapped" > "$TARGET_TTY" 2>/dev/null || true
    else
        printf '%s' "$seq" > "$TARGET_TTY" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Title
# ---------------------------------------------------------------------------
set_title() {
    local text="$1"
    emit $'\e]2;'"$text"$'\e\\'
}

restore_title() {
    emit $'\e]2;\e\\'
}

# ---------------------------------------------------------------------------
# Background color (OSC 11)
# ---------------------------------------------------------------------------
supports_bg_color() {
    case "$TERMINAL_TYPE" in
        apple_terminal|unknown) return 1 ;;
        *) return 0 ;;
    esac
}

set_bg_color() {
    local hex="$1"
    if ! supports_bg_color; then
        return
    fi
    emit $'\e]11;#'"$hex"$'\e\\'
}

restore_bg_color() {
    if ! supports_bg_color; then
        return
    fi
    # OSC 111 resets to default on most terminals
    emit $'\e]111\e\\'
}

# ---------------------------------------------------------------------------
# Desktop notifications
# ---------------------------------------------------------------------------
send_notify() {
    local title="$1"
    local body="$2"
    case "$TERMINAL_TYPE" in
        iterm2|wezterm|ghostty|alacritty|windows_terminal)
            emit $'\e]9;'"$body"$'\e\\'
            ;;
        kitty|vte)
            emit $'\e]777;notify;'"$title"';'"$body"$'\e\\'
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Bell
# ---------------------------------------------------------------------------
bell() {
    emit $'\a'
}

# ---------------------------------------------------------------------------
# iTerm2 attention
# ---------------------------------------------------------------------------
iterm2_attention() {
    if [ "$TERMINAL_TYPE" = "iterm2" ]; then
        emit $'\e]1337;RequestAttention=yes\e\\'
    fi
}

# ---------------------------------------------------------------------------
# Public entry point
# Called by agent-state.sh: source backends/terminal.sh; terminal_apply <state> <tty> <state_file>
# ---------------------------------------------------------------------------
terminal_apply() {
    local state="$1"
    TARGET_TTY="$2"
    local state_file="$3"

    detect_terminal

    local bg_needs_input="3b3000"
    local bg_done="002b00"

    case "$state" in
        running)
            set_title "Running..."
            ;;
        needs-input)
            set_title "Needs Input"
            set_bg_color "$bg_needs_input"
            send_notify "Agent" "Needs input"
            bell
            iterm2_attention
            ;;
        done)
            set_title "Done"
            set_bg_color "$bg_done"
            send_notify "Agent" "Done"
            # Restore bg after 3 seconds if still in done state
            (
                sleep 3
                if [ -f "$state_file" ] && [ "$(head -1 "$state_file" 2>/dev/null)" = "done" ]; then
                    if [ "$IN_TMUX" = true ]; then
                        local seq
                        seq=$(printf '\e]111\e\\')
                        local wrapped
                        wrapped=$(printf '%s' "$seq" | sed 's/\x1b/\x1b\x1b/g')
                        printf '\ePtmux;%s\e\\' "$wrapped" > "$TARGET_TTY" 2>/dev/null || true
                    else
                        printf '\e]111\e\\' > "$TARGET_TTY" 2>/dev/null || true
                    fi
                fi
            ) &
            disown 2>/dev/null || true
            ;;
        off)
            restore_title
            restore_bg_color
            ;;
    esac
}
