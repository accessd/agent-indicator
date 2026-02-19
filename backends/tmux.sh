#!/usr/bin/env bash
# Tmux backend: pane background, active border, window status styling.

set -euo pipefail

# ---------------------------------------------------------------------------
# Tmux helpers
# ---------------------------------------------------------------------------
tmux_get_env() {
    local key="$1"
    tmux show-environment -g "$key" 2>/dev/null | sed 's/^[^=]*=//' || true
}

tmux_set_env() {
    tmux set-environment -g "$1" "$2"
}

tmux_unset_env() {
    tmux set-environment -gu "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Save/restore window options
# ---------------------------------------------------------------------------
save_window_option_once() {
    local window_id="$1"
    local option="$2"
    local env_key="$3"
    local marker="__UNSET__"

    local existing
    existing=$(tmux_get_env "$env_key")
    if [ -n "$existing" ]; then
        return
    fi

    local saved
    saved=$(tmux show-window-option -qvt "$window_id" "$option" 2>/dev/null || true)
    if [ -z "$saved" ]; then
        tmux_set_env "$env_key" "$marker"
    else
        tmux_set_env "$env_key" "$saved"
    fi
}

restore_window_option() {
    local window_id="$1"
    local option="$2"
    local env_key="$3"
    local marker="__UNSET__"

    local saved
    saved=$(tmux_get_env "$env_key")
    if [ -z "$saved" ]; then
        return
    fi
    if [ "$saved" = "$marker" ]; then
        tmux set-window-option -qt "$window_id" -u "$option" || true
    else
        tmux set-window-option -qt "$window_id" "$option" "$saved"
    fi
    tmux_unset_env "$env_key"
}

# ---------------------------------------------------------------------------
# Pane/border/window styling
# ---------------------------------------------------------------------------
apply_pane_style() {
    local pane_id="$1"
    local bg="$2"
    tmux select-pane -t "$pane_id" -P "bg=$bg"
}

reset_pane_style() {
    local pane_id="$1"
    tmux select-pane -t "$pane_id" -P "bg=default"
}

apply_active_border() {
    local window_id="$1"
    local color="$2"
    local orig_key="AGENT_IND_${window_id}_ORIG_BORDER"
    save_window_option_once "$window_id" "pane-active-border-style" "$orig_key"
    tmux set-window-option -qt "$window_id" pane-active-border-style "fg=$color,bold"
}

restore_active_border() {
    local window_id="$1"
    local orig_key="AGENT_IND_${window_id}_ORIG_BORDER"
    restore_window_option "$window_id" "pane-active-border-style" "$orig_key"
}

apply_window_title_style() {
    local window_id="$1"
    local bg="$2"
    local fg="$3"

    if [ -z "$bg" ] || [ -z "$fg" ]; then
        return
    fi

    local status_key="AGENT_IND_${window_id}_ORIG_STATUS"
    local current_key="AGENT_IND_${window_id}_ORIG_CURRENT"
    save_window_option_once "$window_id" "window-status-style" "$status_key"
    save_window_option_once "$window_id" "window-status-current-style" "$current_key"
    tmux set-window-option -qt "$window_id" window-status-style "bg=$bg,fg=$fg"
    tmux set-window-option -qt "$window_id" window-status-current-style "bg=$bg,fg=$fg"
}

clear_window_title_style() {
    local window_id="$1"
    [ -z "$window_id" ] && return
    local status_key="AGENT_IND_${window_id}_ORIG_STATUS"
    local current_key="AGENT_IND_${window_id}_ORIG_CURRENT"
    restore_window_option "$window_id" "window-status-style" "$status_key"
    restore_window_option "$window_id" "window-status-current-style" "$current_key"
}

# ---------------------------------------------------------------------------
# Resolve target pane
# ---------------------------------------------------------------------------
resolve_pane() {
    if [ -n "${TMUX_PANE:-}" ]; then
        printf '%s' "$TMUX_PANE"
    else
        tmux display-message -p '#{pane_id}'
    fi
}

pane_exists() {
    local pane_id="$1"
    [ -n "$pane_id" ] || return 1
    tmux display-message -p -t "$pane_id" '#{pane_id}' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Default colors per state
# ---------------------------------------------------------------------------
default_border_color() {
    case "$1" in
        needs-input) printf 'yellow' ;;
        done) printf 'green' ;;
        *) printf '' ;;
    esac
}

default_title_bg() {
    case "$1" in
        needs-input) printf 'yellow' ;;
        done) printf 'red' ;;
        *) printf '' ;;
    esac
}

default_title_fg() {
    case "$1" in
        needs-input) printf 'black' ;;
        done) printf 'black' ;;
        *) printf '' ;;
    esac
}

# ---------------------------------------------------------------------------
# Public entry point
# Called by agent-state.sh: source backends/tmux.sh; tmux_apply <state> <agent>
# ---------------------------------------------------------------------------
tmux_apply() {
    local state="$1"
    local agent="$2"

    local pane_id
    pane_id=$(resolve_pane)
    if ! pane_exists "$pane_id"; then
        return
    fi

    local window_id
    window_id=$(tmux display-message -p -t "$pane_id" '#{window_id}')

    local state_key="AGENT_IND_PANE_${pane_id}_STATE"
    local agent_key="AGENT_IND_PANE_${pane_id}_AGENT"
    local done_key="AGENT_IND_PANE_${pane_id}_DONE"

    local border_color title_bg title_fg
    border_color=$(default_border_color "$state")
    title_bg=$(default_title_bg "$state")
    title_fg=$(default_title_fg "$state")

    case "$state" in
        running)
            clear_window_title_style "$window_id"
            tmux_unset_env "$done_key"
            tmux_set_env "$state_key" "$state"
            tmux_set_env "$agent_key" "$agent"
            reset_pane_style "$pane_id"
            if [ -n "$border_color" ]; then
                apply_active_border "$window_id" "$border_color"
            else
                restore_active_border "$window_id"
            fi
            ;;
        needs-input)
            clear_window_title_style "$window_id"
            tmux_unset_env "$done_key"
            tmux_set_env "$state_key" "$state"
            tmux_set_env "$agent_key" "$agent"
            reset_pane_style "$pane_id"
            if [ -n "$border_color" ]; then
                apply_active_border "$window_id" "$border_color"
            fi
            apply_window_title_style "$window_id" "$title_bg" "$title_fg"
            ;;
        done)
            tmux_set_env "$state_key" "done"
            tmux_set_env "$agent_key" "$agent"
            tmux_set_env "$done_key" "1"
            reset_pane_style "$pane_id"
            if [ -n "$border_color" ]; then
                apply_active_border "$window_id" "$border_color"
            fi
            apply_window_title_style "$window_id" "$title_bg" "$title_fg"
            ;;
        off)
            clear_window_title_style "$window_id"
            tmux_unset_env "$done_key"
            tmux_unset_env "$state_key"
            tmux_unset_env "$agent_key"
            reset_pane_style "$pane_id"
            restore_active_border "$window_id"
            ;;
    esac

    tmux refresh-client -S >/dev/null 2>&1 || true
}
