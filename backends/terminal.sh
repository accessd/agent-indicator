#!/usr/bin/env bash
# Terminal backend: tab title, background color, desktop notifications, bell.
# Uses native terminal escape sequences. Wraps in tmux passthrough when needed.

set -euo pipefail

# ---------------------------------------------------------------------------
# Terminal detection
# ---------------------------------------------------------------------------
TERMINAL_TYPE="unknown"
IN_TMUX=false

_detect_term_program() {
    local tp="$1"
    case "$tp" in
        iTerm.app)      TERMINAL_TYPE="iterm2" ;;
        WezTerm)        TERMINAL_TYPE="wezterm" ;;
        ghostty)        TERMINAL_TYPE="ghostty" ;;
        Apple_Terminal) TERMINAL_TYPE="apple_terminal" ;;
        *)              return 1 ;;
    esac
}

detect_terminal() {
    if [ -n "${TMUX:-}" ]; then
        IN_TMUX=true
    fi

    # Direct env detection (works outside tmux)
    if [ -n "${KITTY_PID:-}" ]; then
        TERMINAL_TYPE="kitty"
    elif _detect_term_program "${TERM_PROGRAM:-}"; then
        true
    elif [ -n "${WT_SESSION:-}" ]; then
        TERMINAL_TYPE="windows_terminal"
    elif [ -n "${VTE_VERSION:-}" ]; then
        TERMINAL_TYPE="vte"
    elif [ -n "${ALACRITTY_SOCKET:-}" ]; then
        TERMINAL_TYPE="alacritty"
    elif [ "$IN_TMUX" = true ]; then
        # Inside tmux, env vars reflect tmux, not the outer terminal.
        # Ask tmux for the original TERM_PROGRAM (session env, then global).
        local outer_tp=""
        outer_tp=$(tmux show-environment TERM_PROGRAM 2>/dev/null | sed 's/^TERM_PROGRAM=//' || true)
        if [ -z "$outer_tp" ] || [ "$outer_tp" = "-TERM_PROGRAM" ]; then
            outer_tp=$(tmux show-environment -g TERM_PROGRAM 2>/dev/null | sed 's/^TERM_PROGRAM=//' || true)
        fi
        if [ -n "$outer_tp" ] && [ "$outer_tp" != "-TERM_PROGRAM" ]; then
            _detect_term_program "$outer_tp" || true
        fi
        # Kitty detection via tmux env
        if [ "$TERMINAL_TYPE" = "unknown" ]; then
            local outer_kitty=""
            outer_kitty=$(tmux show-environment KITTY_PID 2>/dev/null | sed 's/^KITTY_PID=//' || true)
            if [ -z "$outer_kitty" ] || [ "$outer_kitty" = "-KITTY_PID" ]; then
                outer_kitty=$(tmux show-environment -g KITTY_PID 2>/dev/null | sed 's/^KITTY_PID=//' || true)
            fi
            if [ -n "$outer_kitty" ] && [ "$outer_kitty" != "-KITTY_PID" ]; then
                TERMINAL_TYPE="kitty"
            fi
        fi
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
    if [ "$IN_TMUX" = true ]; then
        tmux select-pane -T "$text" 2>/dev/null || true
    fi
    emit $'\e]2;'"$text"$'\e\\'
}

restore_title() {
    if [ "$IN_TMUX" = true ]; then
        tmux select-pane -T "" 2>/dev/null || true
    fi
    emit $'\e]2;\e\\'
}

# ---------------------------------------------------------------------------
# Background color (OSC 11)
# ---------------------------------------------------------------------------
supports_bg_color() {
    case "$TERMINAL_TYPE" in
        apple_terminal) return 1 ;;
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

    local bg_needs_input="${AGENT_INDICATOR_TERMINAL_BG_NEEDS_INPUT:-3b3000}"
    local bg_done="${AGENT_INDICATOR_TERMINAL_BG_DONE:-002b00}"

    case "$state" in
        running)
            restore_bg_color
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
            # Restore bg after timeout if still in done state (0 = never restore)
            local bg_timeout="${AGENT_INDICATOR_TERMINAL_BG_RESTORE_TIMEOUT:-3}"
            if [ "$bg_timeout" != "0" ]; then
                (
                    sleep "$bg_timeout"
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
            fi
            ;;
        off)
            restore_title
            restore_bg_color
            ;;
    esac
}
