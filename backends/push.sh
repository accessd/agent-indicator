#!/usr/bin/env bash
# Push notification backend: ntfy, Pushover, Telegram.
# Requires curl. All requests are backgrounded.

set -euo pipefail

# ---------------------------------------------------------------------------
# Service adapters
# ---------------------------------------------------------------------------
_push_ntfy() {
    local title="$1" body="$2"
    local server="${AGENT_INDICATOR_PUSH_SERVER:-https://ntfy.sh}"
    local topic="${AGENT_INDICATOR_PUSH_TOPIC:-}"
    local token="${AGENT_INDICATOR_PUSH_TOKEN:-}"

    if [ -z "$topic" ]; then
        return
    fi

    if [ -n "$token" ]; then
        curl -fsSL -X POST \
            -H "Title: $title" \
            -H "Priority: high" \
            -H "Tags: bell" \
            -H "Authorization: Bearer $token" \
            -d "$body" \
            "${server}/${topic}" >/dev/null 2>&1 &
    else
        curl -fsSL -X POST \
            -H "Title: $title" \
            -H "Priority: high" \
            -H "Tags: bell" \
            -d "$body" \
            "${server}/${topic}" >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
}

_push_pushover() {
    local title="$1" body="$2"
    local token="${AGENT_INDICATOR_PUSH_TOKEN:-}"
    local user="${AGENT_INDICATOR_PUSH_TOPIC:-}"  # topic doubles as user key for pushover

    if [ -z "$token" ] || [ -z "$user" ]; then
        return
    fi

    curl -fsSL -X POST \
        -d "token=$token" \
        -d "user=$user" \
        -d "title=$title" \
        -d "message=$body" \
        -d "priority=1" \
        "https://api.pushover.net/1/messages.json" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

_push_telegram() {
    local title="$1" body="$2"
    local token="${AGENT_INDICATOR_PUSH_TOKEN:-}"
    local chat_id="${AGENT_INDICATOR_PUSH_TOPIC:-}"  # topic doubles as chat_id for telegram

    if [ -z "$token" ] || [ -z "$chat_id" ]; then
        return
    fi

    local text="*${title}*"$'\n'"${body}"

    curl -fsSL -X POST \
        -d "chat_id=$chat_id" \
        -d "text=$text" \
        -d "parse_mode=Markdown" \
        "https://api.telegram.org/bot${token}/sendMessage" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Format templates (same logic as desktop.sh)
# ---------------------------------------------------------------------------
_push_format() {
    local template="$1" state="$2" agent="$3"
    local result="$template"
    result="${result//\{state\}/$state}"
    result="${result//\{agent\}/$agent}"
    printf '%s' "$result"
}

# ---------------------------------------------------------------------------
# Public entry point
# Called by agent-state.sh: source backends/push.sh; push_apply <state> <agent>
#
# Env vars (set by config system or user):
#   AGENT_INDICATOR_PUSH_SERVICE             - ntfy/pushover/telegram
#   AGENT_INDICATOR_PUSH_SERVER              - ntfy server URL
#   AGENT_INDICATOR_PUSH_TOPIC              - topic/user/chat_id
#   AGENT_INDICATOR_PUSH_TOKEN              - auth token
#   AGENT_INDICATOR_PUSH_STATE_NEEDS_INPUT  - on/off
#   AGENT_INDICATOR_PUSH_STATE_DONE         - on/off
# ---------------------------------------------------------------------------
push_apply() {
    local state="$1"
    local agent="${2:-claude}"

    if ! command -v curl >/dev/null 2>&1; then
        return
    fi

    case "$state" in
        needs-input)
            if [ "${AGENT_INDICATOR_PUSH_STATE_NEEDS_INPUT:-on}" = "off" ]; then
                return
            fi
            ;;
        done)
            if [ "${AGENT_INDICATOR_PUSH_STATE_DONE:-on}" = "off" ]; then
                return
            fi
            ;;
        *)
            return
            ;;
    esac

    local title="Agent: $state"
    local body="$agent is $state"
    local service="${AGENT_INDICATOR_PUSH_SERVICE:-ntfy}"

    case "$service" in
        ntfy)     _push_ntfy "$title" "$body" ;;
        pushover) _push_pushover "$title" "$body" ;;
        telegram) _push_telegram "$title" "$body" ;;
    esac
}
