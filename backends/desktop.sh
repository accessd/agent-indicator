#!/usr/bin/env bash
# Desktop notification backend.
# macOS: osascript (builtin), terminal-notifier (optional, prettier).
# Linux: notify-send (libnotify).
# WSL: powershell toast via BurntToast or basic wsl-notify-send.

set -euo pipefail

# ---------------------------------------------------------------------------
# Notification dispatch
# ---------------------------------------------------------------------------
_notify_macos_osascript() {
    local title="$1" body="$2"
    osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null &
    disown 2>/dev/null || true
}

_notify_macos_terminal_notifier() {
    local title="$1" body="$2"
    terminal-notifier -title "$title" -message "$body" -group "agent-indicator" 2>/dev/null &
    disown 2>/dev/null || true
}

_notify_linux() {
    local title="$1" body="$2"
    notify-send -a "agent-indicator" -u normal "$title" "$body" 2>/dev/null &
    disown 2>/dev/null || true
}

_send_desktop_notification() {
    local title="$1" body="$2"

    case "${PLATFORM:-}" in
        macos)
            if command -v terminal-notifier >/dev/null 2>&1; then
                _notify_macos_terminal_notifier "$title" "$body"
            else
                _notify_macos_osascript "$title" "$body"
            fi
            ;;
        linux|wsl)
            if command -v notify-send >/dev/null 2>&1; then
                _notify_linux "$title" "$body"
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Format templates
# ---------------------------------------------------------------------------
_format() {
    local template="$1" state="$2" agent="$3"
    local result="$template"
    result="${result//\{state\}/$state}"
    result="${result//\{agent\}/$agent}"
    printf '%s' "$result"
}

# ---------------------------------------------------------------------------
# Public entry point
# Called by agent-state.sh: source backends/desktop.sh; desktop_apply <state> <agent>
#
# Env vars (set by config system or user):
#   AGENT_INDICATOR_DESKTOP_STATE_NEEDS_INPUT - on/off
#   AGENT_INDICATOR_DESKTOP_STATE_DONE        - on/off
#   AGENT_INDICATOR_DESKTOP_TITLE_FORMAT      - e.g. "[{agent}] {state}"
#   AGENT_INDICATOR_DESKTOP_BODY_FORMAT       - e.g. "{agent} is {state}"
# ---------------------------------------------------------------------------
desktop_apply() {
    local state="$1"
    local agent="${2:-claude}"

    case "$state" in
        needs-input)
            if [ "${AGENT_INDICATOR_DESKTOP_STATE_NEEDS_INPUT:-on}" = "off" ]; then
                return
            fi
            ;;
        done)
            if [ "${AGENT_INDICATOR_DESKTOP_STATE_DONE:-on}" = "off" ]; then
                return
            fi
            ;;
        *)
            return
            ;;
    esac

    local title_fmt="${AGENT_INDICATOR_DESKTOP_TITLE_FORMAT:-[{agent}] {state}}"
    local body_fmt="${AGENT_INDICATOR_DESKTOP_BODY_FORMAT:-{agent} is {state}}"

    local title body
    title=$(_format "$title_fmt" "$state" "$agent")
    body=$(_format "$body_fmt" "$state" "$agent")

    _send_desktop_notification "$title" "$body"
}
