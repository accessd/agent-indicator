#!/usr/bin/env bash
# shellcheck disable=SC2034
# Platform and tool detection helpers.
#
# After sourcing, the following variables are set:
#   PLATFORM_OS     - "macos", "linux", "wsl", or "unknown"
#   PLATFORM        - alias for PLATFORM_OS (backward compat)
#   HAS_TMUX        - "true"/"false"
#   HAS_PYTHON3     - "true"/"false"
#   HAS_CURL        - "true"/"false"
#   HAS_BREW        - "true"/"false"
#   HAS_BC          - "true"/"false"
#   HAS_AFPLAY      - "true"/"false"
#   HAS_PAPLAY      - "true"/"false"
#   HAS_APLAY       - "true"/"false"
#   HAS_PLAY        - "true"/"false"
#   HAS_OSASCRIPT   - "true"/"false"
#   HAS_NOTIFY_SEND - "true"/"false"
#   HAS_TERM_NOTIFIER - "true"/"false"
#   IN_TMUX_SESSION - "true"/"false"

set -euo pipefail

_has() { command -v "$1" >/dev/null 2>&1; }

detect_platform() {
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo unknown)"
    case "$uname_s" in
        Darwin) PLATFORM_OS="macos" ;;
        Linux)
            if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
                PLATFORM_OS="wsl"
            else
                PLATFORM_OS="linux"
            fi
            ;;
        *) PLATFORM_OS="unknown" ;;
    esac
    PLATFORM="$PLATFORM_OS"
}

detect_tools() {
    HAS_TMUX="false";          _has tmux && HAS_TMUX="true"
    HAS_PYTHON3="false";       _has python3 && HAS_PYTHON3="true"
    HAS_CURL="false";          _has curl && HAS_CURL="true"
    HAS_BREW="false";          _has brew && HAS_BREW="true"
    HAS_BC="false";            _has bc && HAS_BC="true"
    HAS_AFPLAY="false";        _has afplay && HAS_AFPLAY="true"
    HAS_PAPLAY="false";        _has paplay && HAS_PAPLAY="true"
    HAS_APLAY="false";         _has aplay && HAS_APLAY="true"
    HAS_PLAY="false";          _has play && HAS_PLAY="true"
    HAS_OSASCRIPT="false";     _has osascript && HAS_OSASCRIPT="true"
    HAS_NOTIFY_SEND="false";   _has notify-send && HAS_NOTIFY_SEND="true"
    HAS_TERM_NOTIFIER="false"; _has terminal-notifier && HAS_TERM_NOTIFIER="true"

    IN_TMUX_SESSION="false"
    if [ -n "${TMUX:-}" ] && [ "$HAS_TMUX" = "true" ]; then
        IN_TMUX_SESSION="true"
    fi
}

detect_platform
detect_tools
