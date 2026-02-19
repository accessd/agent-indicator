#!/usr/bin/env bash
# Stderr logger with verbosity levels.
#
# Usage (after sourcing):
#   log_debug "verbose detail"
#   log_info  "normal message"
#   log_warn  "something off"
#   log_error "fatal problem"
#
# Levels: quiet=0, error=1, warn=2, info=3, debug=4
# Set via AGENT_INDICATOR_LOG_LEVEL (name or number).
# AGENT_INDICATOR_QUIET=1 forces quiet.

_ai_log_resolve_level() {
    case "$1" in
        quiet|0) echo 0 ;;
        error|1) echo 1 ;;
        warn|2)  echo 2 ;;
        info|3)  echo 3 ;;
        debug|4) echo 4 ;;
        *)       echo 2 ;;
    esac
}

_AI_LOG_LEVEL="$(_ai_log_resolve_level "${AGENT_INDICATOR_LOG_LEVEL:-warn}")"

if [ "${AGENT_INDICATOR_QUIET:-0}" = "1" ]; then
    _AI_LOG_LEVEL=0
fi

_log() {
    local level="$1" prefix="$2"
    shift 2
    if [ "$_AI_LOG_LEVEL" -ge "$level" ]; then
        printf '[agent-indicator] %s: %s\n' "$prefix" "$*" >&2
    fi
}

log_error() { _log 1 "ERROR" "$@"; }
log_warn()  { _log 2 "WARN"  "$@"; }
log_info()  { _log 3 "INFO"  "$@"; }
log_debug() { _log 4 "DEBUG" "$@"; }
