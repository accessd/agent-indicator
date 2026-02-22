#!/usr/bin/env bash
# Codex notify adapter for agent-indicator.
# Called by Codex with an event name as $1.
# Maps Codex events to agent-indicator states.

set -euo pipefail

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_STATE="${AGENT_INDICATOR_DIR:-$ADAPTER_DIR/..}/agent-state.sh"

event="${1:-}"

case "$event" in
    start|session-start|turn-start|working)
        state="running"
        ;;
    permission*|approve*|needs-input|input-required|ask-user)
        state="needs-input"
        ;;
    agent-turn-complete|complete|done|stop|error|fail*)
        state="done"
        ;;
    *)
        state="done"
        ;;
esac

exec "$AGENT_STATE" --agent codex --state "$state"
