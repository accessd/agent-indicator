#!/usr/bin/env bash
# agent-indicator: dispatch agent state to terminal, tmux, sound, desktop, and push backends.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${TMPDIR:-/tmp}"

usage() {
    cat <<'EOF' >&2
Usage: agent-state.sh --state <running|needs-input|done|off> [--agent <name>] [--tty /dev/ttysXXX]

Backends (configure via ~/.config/agent-indicator/config.json or env vars):
  AGENT_INDICATOR_TERMINAL=on|off   Terminal escape sequences (default: on)
  AGENT_INDICATOR_TMUX=on|off       Tmux pane/border styling (default: auto)
  AGENT_INDICATOR_SOUND=on|off      Audio alerts (default: off)
  AGENT_INDICATOR_DESKTOP=on|off    Desktop notifications (default: off)
  AGENT_INDICATOR_PUSH=on|off       Push notifications (default: off)
EOF
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
STATE=""
AGENT="claude"
TTY_OVERRIDE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --state)
            [ "$#" -lt 2 ] && usage && exit 1
            STATE="$2"
            shift 2
            ;;
        --agent)
            [ "$#" -lt 2 ] && usage && exit 1
            AGENT="$2"
            shift 2
            ;;
        --tty)
            [ "$#" -lt 2 ] && usage && exit 1
            TTY_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [ -z "$STATE" ]; then
    usage
    exit 1
fi

case "$STATE" in
    running|needs-input|done|off) ;;
    *)
        usage
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Load config (if python3 available and config system exists)
# Env vars set directly by the user take priority over config.json values.
# ---------------------------------------------------------------------------
CONFIG_PY="$SCRIPT_DIR/config/config.py"
if command -v python3 >/dev/null 2>&1 && [ -f "$CONFIG_PY" ]; then
    _exports=$(python3 "$CONFIG_PY" --shell-exports 2>/dev/null || true)
    if [ -n "$_exports" ]; then
        eval "$_exports"
    fi
fi

# ---------------------------------------------------------------------------
# Source libs
# ---------------------------------------------------------------------------
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

log_debug "state=$STATE agent=$AGENT platform=$PLATFORM"

# ---------------------------------------------------------------------------
# TTY resolution
# ---------------------------------------------------------------------------
resolve_tty() {
    if [ -n "$TTY_OVERRIDE" ]; then
        printf '%s' "$TTY_OVERRIDE"
        return
    fi
    local t
    t=$(tty 2>/dev/null) || true
    if [ -n "$t" ] && [ "$t" != "not a tty" ]; then
        printf '%s' "$t"
        return
    fi
    printf '%s' "/dev/tty"
}

TARGET_TTY=$(resolve_tty)

# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------
tty_slug="${TARGET_TTY//\//_}"
STATE_FILE="${STATE_DIR}/agent-indicator-${tty_slug}"

if [ "$STATE" = "off" ]; then
    rm -f "$STATE_FILE"
else
    printf '%s\n' "$STATE" > "$STATE_FILE"
fi

# ---------------------------------------------------------------------------
# Backend detection
# ---------------------------------------------------------------------------
opt_terminal="${AGENT_INDICATOR_TERMINAL:-on}"
opt_sound="${AGENT_INDICATOR_SOUND:-off}"
opt_desktop="${AGENT_INDICATOR_DESKTOP:-off}"
opt_push="${AGENT_INDICATOR_PUSH:-off}"

# Tmux: "auto" means detect, "on"/"off" are explicit
opt_tmux="${AGENT_INDICATOR_TMUX:-auto}"
if [ "$opt_tmux" = "auto" ]; then
    if [ "$IN_TMUX_SESSION" = "true" ]; then
        opt_tmux="on"
    else
        opt_tmux="off"
    fi
fi

is_on() {
    case "$1" in
        on|true|yes|1) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Dispatch
# Each backend is sourced and called independently. If one fails, others
# still fire. Errors go to stderr only.
# ---------------------------------------------------------------------------
if is_on "$opt_terminal"; then
    log_debug "dispatching terminal backend"
    # shellcheck source=backends/terminal.sh
    source "$SCRIPT_DIR/backends/terminal.sh"
    terminal_apply "$STATE" "$TARGET_TTY" "$STATE_FILE" || log_warn "terminal backend failed"
fi

if is_on "$opt_tmux"; then
    log_debug "dispatching tmux backend"
    # shellcheck source=backends/tmux.sh
    source "$SCRIPT_DIR/backends/tmux.sh"
    tmux_apply "$STATE" "$AGENT" || log_warn "tmux backend failed"
fi

if is_on "$opt_sound"; then
    log_debug "dispatching sound backend"
    # shellcheck source=backends/sound.sh
    source "$SCRIPT_DIR/backends/sound.sh"
    sound_apply "$STATE" || log_warn "sound backend failed"
fi

if is_on "$opt_desktop"; then
    log_debug "dispatching desktop backend"
    # shellcheck source=backends/desktop.sh
    source "$SCRIPT_DIR/backends/desktop.sh"
    desktop_apply "$STATE" "$AGENT" || log_warn "desktop backend failed"
fi

if is_on "$opt_push"; then
    log_debug "dispatching push backend"
    # shellcheck source=backends/push.sh
    source "$SCRIPT_DIR/backends/push.sh"
    push_apply "$STATE" "$AGENT" || log_warn "push backend failed"
fi
