#!/usr/bin/env bash
# Interactive setup wizard for agent-indicator.
# Detects platform, walks through backend configuration, writes config, patches hooks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source libs
# ---------------------------------------------------------------------------
# shellcheck source=lib/log.sh
source "$SCRIPT_DIR/lib/log.sh"
# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"

CONFIG_PY="$SCRIPT_DIR/config/config.py"
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for the setup wizard." >&2
    echo "You can edit config.json directly. See README.md." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
BOLD=$'\033[1m'
DIM=$'\033[2m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
RESET=$'\033[0m'

header() {
    printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"
    printf '%s%s%s\n' "$DIM" "$(printf '%.0s-' $(seq 1 ${#1}))" "$RESET"
}

ok()   { printf '  %s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s[!]%s %s\n' "$YELLOW" "$RESET" "$1"; }
skip() { printf '  %s[-]%s %s\n' "$DIM" "$RESET" "$1"; }

ask_yn() {
    local prompt="$1" default="${2:-y}"
    local yn
    if [ "$default" = "y" ]; then
        printf '  %s [Y/n] ' "$prompt"
    else
        printf '  %s [y/N] ' "$prompt"
    fi
    read -r yn </dev/tty
    yn="${yn:-$default}"
    case "$yn" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

ask_input() {
    local prompt="$1" default="${2:-}"
    if [ -n "$default" ]; then
        printf '  %s [%s]: ' "$prompt" "$default" >/dev/tty
    else
        printf '  %s: ' "$prompt" >/dev/tty
    fi
    local val
    read -r val </dev/tty
    printf '%s' "${val:-$default}"
}

ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    printf '  %s\n' "$prompt" >/dev/tty
    local i=1
    for opt in "${options[@]}"; do
        printf '    %s%d%s) %s\n' "$CYAN" "$i" "$RESET" "$opt" >/dev/tty
        ((i++))
    done
    printf '  Choice: ' >/dev/tty
    local choice
    read -r choice </dev/tty
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        printf '%s' "${options[$((choice-1))]}"
    else
        printf '%s' "${options[0]}"
    fi
}

cfg_set() {
    python3 "$CONFIG_PY" --set "$1" "$2"
}

# ---------------------------------------------------------------------------
# Setup sections
# ---------------------------------------------------------------------------
setup_platform() {
    header "Platform Detection"
    printf '  Platform: %s%s%s\n' "$BOLD" "$PLATFORM" "$RESET"
    if [ "$HAS_TMUX" = "true" ];          then ok "tmux";             else skip "tmux not found"; fi
    if [ "$IN_TMUX_SESSION" = "true" ];    then ok "inside tmux";      else skip "not inside tmux"; fi
    if [ "$HAS_AFPLAY" = "true" ];         then ok "afplay (macOS)";   else skip "afplay not found"; fi
    if [ "$HAS_PAPLAY" = "true" ];         then ok "paplay (Linux)";   else skip "paplay not found"; fi
    if [ "$HAS_TERM_NOTIFIER" = "true" ];  then ok "terminal-notifier"; else skip "terminal-notifier not found"; fi
    if [ "$HAS_NOTIFY_SEND" = "true" ];    then ok "notify-send";      else skip "notify-send not found"; fi
    if [ "$HAS_CURL" = "true" ];           then ok "curl";             else skip "curl not found"; fi
}

setup_terminal() {
    header "1. Terminal Notifications"
    printf '  Changes tab title, background color, and sends terminal notifications.\n'
    printf '  Works in most modern terminals (iTerm2, Kitty, WezTerm, Ghostty, etc.)\n'
    if ask_yn "Enable terminal backend?" "y"; then
        cfg_set "backends.terminal.enabled" "true"
        ok "terminal: enabled"
    else
        cfg_set "backends.terminal.enabled" "false"
        skip "terminal: disabled"
    fi
}

setup_tmux() {
    header "2. Tmux Styling"
    printf '  For tmux pane borders, window status, and animation use tmux-agent-indicator.\n'
    printf '  https://github.com/accessd/tmux-agent-indicator\n'
    if [ "$HAS_TMUX" != "true" ]; then
        skip "tmux not found, skipping"
        return
    fi
    if ! ask_yn "Install tmux-agent-indicator plugin?" "y"; then
        skip "tmux-agent-indicator: skipped"
        return
    fi
    if curl -fsSL https://raw.githubusercontent.com/accessd/tmux-agent-indicator/main/install.sh | bash; then
        ok "tmux-agent-indicator installed"
    else
        warn "tmux-agent-indicator install failed"
    fi
    printf '  See tmux-agent-indicator README for config options.\n'
}

setup_sound() {
    header "3. Sound Alerts"
    printf '  Plays a sound when the agent needs input or finishes.\n'
    local has_player="false"
    if [ "$HAS_AFPLAY" = "true" ] || [ "$HAS_PAPLAY" = "true" ] || [ "$HAS_APLAY" = "true" ] || [ "$HAS_PLAY" = "true" ]; then
        has_player="true"
    fi
    if [ "$has_player" = "false" ]; then
        printf '  %sNo audio player found. Sound backend requires afplay, paplay, aplay, or play.%s\n' "$YELLOW" "$RESET"
    fi
    if ask_yn "Enable sound backend?" "n"; then
        cfg_set "backends.sound.enabled" "true"

        # Discover available packs
        local packs_dir="$SCRIPT_DIR/packs"
        local pack_dirs=() pack_labels=()
        for manifest in "$packs_dir"/*/openpeon.json; do
            [ -f "$manifest" ] || continue
            local dir_name pack_name
            dir_name="$(basename "$(dirname "$manifest")")"
            pack_name="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('name',sys.argv[2]))" "$manifest" "$dir_name" 2>/dev/null || echo "$dir_name")"
            pack_dirs+=("$dir_name")
            pack_labels+=("$pack_name ($dir_name)")
        done

        local pack_id
        if [ "${#pack_dirs[@]}" -gt 1 ]; then
            local choice
            choice=$(ask_choice "Sound pack:" "${pack_labels[@]}")
            # Extract dir name from "Label (dirname)" format
            pack_id="$(echo "$choice" | sed 's/.*(\(.*\))/\1/')"
        else
            pack_id="${pack_dirs[0]:-default}"
        fi
        cfg_set "backends.sound.pack" "$pack_id"

        local vol
        vol=$(ask_input "Volume (0.0-1.0)" "0.7")
        cfg_set "backends.sound.volume" "$vol"
        if ask_yn "Play sound on needs-input?" "y"; then
            cfg_set "backends.sound.states.needs-input" "true"
        else
            cfg_set "backends.sound.states.needs-input" "false"
        fi
        if ask_yn "Play sound on done?" "y"; then
            cfg_set "backends.sound.states.done" "true"
        else
            cfg_set "backends.sound.states.done" "false"
        fi
        ok "sound: enabled (pack: $pack_id, volume: $vol)"
    else
        cfg_set "backends.sound.enabled" "false"
        skip "sound: disabled"
    fi
}

setup_desktop() {
    header "4. Desktop Notifications"
    printf '  Shows system notifications (separate from terminal-level notifications).\n'
    local desktop_available="false"
    if [ "$PLATFORM" = "macos" ]; then
        desktop_available="true"
        if [ "$HAS_TERM_NOTIFIER" = "false" ]; then
            printf '  Using osascript for notifications (basic).\n'
            if [ "$HAS_BREW" = "true" ]; then
                if ask_yn "Install terminal-notifier via Homebrew for better notifications?" "n"; then
                    if brew install terminal-notifier 2>/dev/null; then
                        ok "terminal-notifier installed"
                    else
                        warn "install failed"
                    fi
                fi
            fi
        else
            ok "terminal-notifier available (rich notifications)"
        fi
    elif [ "$PLATFORM" = "linux" ] || [ "$PLATFORM" = "wsl" ]; then
        if [ "$HAS_NOTIFY_SEND" = "true" ]; then
            desktop_available="true"
        else
            printf '  %snotify-send not found. Install libnotify-bin for desktop notifications.%s\n' "$YELLOW" "$RESET"
        fi
    fi
    if [ "$desktop_available" = "true" ] && ask_yn "Enable desktop notifications?" "n"; then
        cfg_set "backends.desktop.enabled" "true"
        if ask_yn "Notify on needs-input?" "y"; then
            cfg_set "backends.desktop.states.needs-input" "true"
        else
            cfg_set "backends.desktop.states.needs-input" "false"
        fi
        if ask_yn "Notify on done?" "y"; then
            cfg_set "backends.desktop.states.done" "true"
        else
            cfg_set "backends.desktop.states.done" "false"
        fi
        ok "desktop: enabled"
    else
        cfg_set "backends.desktop.enabled" "false"
        skip "desktop: disabled"
    fi
}

setup_push() {
    header "5. Push Notifications"
    printf '  Send notifications to your phone via ntfy, Pushover, or Telegram.\n'
    if [ "$HAS_CURL" = "false" ]; then
        printf '  %scurl not found. Push notifications require curl.%s\n' "$YELLOW" "$RESET"
        cfg_set "backends.push.enabled" "false"
        skip "push: disabled (no curl)"
        return
    fi
    if ! ask_yn "Enable push notifications?" "n"; then
        cfg_set "backends.push.enabled" "false"
        skip "push: disabled"
        return
    fi
    cfg_set "backends.push.enabled" "true"
    local service
    service=$(ask_choice "Which service?" "ntfy (easiest, no signup for public topics)" "Pushover" "Telegram")
    case "$service" in
        ntfy*)
            cfg_set "backends.push.service" "ntfy"
            local server topic token
            server=$(ask_input "ntfy server" "https://ntfy.sh")
            cfg_set "backends.push.server" "$server"
            topic=$(ask_input "Topic name (e.g. my-agent-alerts)" "")
            if [ -z "$topic" ]; then
                topic="agent-$(od -An -tx1 -N6 /dev/urandom | tr -d ' \n')"
                printf '  Generated topic: %s%s%s\n' "$BOLD" "$topic" "$RESET"
            fi
            cfg_set "backends.push.topic" "$topic"
            token=$(ask_input "Access token (optional, press Enter to skip)" "")
            if [ -n "$token" ]; then
                cfg_set "backends.push.token" "$token"
            fi
            printf '  Subscribe at: %s%s/%s%s\n' "$CYAN" "$server" "$topic" "$RESET"
            ;;
        Pushover)
            cfg_set "backends.push.service" "pushover"
            local token user_key
            token=$(ask_input "API token" "")
            cfg_set "backends.push.token" "$token"
            user_key=$(ask_input "User key" "")
            cfg_set "backends.push.topic" "$user_key"
            ;;
        Telegram)
            cfg_set "backends.push.service" "telegram"
            local token chat_id
            token=$(ask_input "Bot token" "")
            cfg_set "backends.push.token" "$token"
            chat_id=$(ask_input "Chat ID" "")
            cfg_set "backends.push.topic" "$chat_id"
            ;;
    esac
    ok "push: enabled ($service)"
}

setup_hooks() {
    header "6. Claude Code Hooks"
    printf '  Hooks connect Claude Code events to agent-indicator.\n'
    if ! ask_yn "Patch ~/.claude/settings.json with hooks?" "y"; then
        skip "hooks: skipped"
        return
    fi
    local claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local claude_settings="$claude_dir/settings.json"
    mkdir -p "$claude_dir"
    if [ ! -f "$claude_settings" ]; then
        printf '{}\n' > "$claude_settings"
    fi
    python3 - "$claude_settings" "$SCRIPT_DIR" "install" <<'PY'
import json, pathlib, sys
settings_path = pathlib.Path(sys.argv[1])
target_dir = sys.argv[2]
try:
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
except Exception:
    settings = {}
hooks = settings.setdefault("hooks", {})
for event in list(hooks.keys()):
    entries = hooks.get(event, [])
    cleaned = []
    for entry in entries:
        hook_items = entry.get("hooks", [])
        filtered = [h for h in hook_items if not ("agent-state.sh" in h.get("command", "") and "agent-indicator" in h.get("command", "") and "tmux-agent-indicator" not in h.get("command", ""))]
        if hook_items and not filtered:
            continue
        if filtered != hook_items:
            entry = dict(entry)
            entry["hooks"] = filtered
        cleaned.append(entry)
    if cleaned:
        hooks[event] = cleaned
    else:
        hooks.pop(event, None)
events = {
    "UserPromptSubmit": f"\"${{AGENT_INDICATOR_DIR:-{target_dir}}}\"/agent-state.sh --state running",
    "PermissionRequest": f"\"${{AGENT_INDICATOR_DIR:-{target_dir}}}\"/agent-state.sh --state needs-input",
    "Stop": f"\"${{AGENT_INDICATOR_DIR:-{target_dir}}}\"/agent-state.sh --state done",
}
for event, command in events.items():
    entries = hooks.get(event, [])
    entries.append({"matcher": "", "hooks": [{"type": "command", "command": command}]})
    hooks[event] = entries
settings["hooks"] = hooks
settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
PY
    ok "hooks patched"
}

setup_codex() {
    header "7. Codex Integration"
    local codex_dir="$HOME/.codex"
    if [ ! -d "$codex_dir" ]; then
        skip "codex: ~/.codex/ not found"
        return
    fi
    printf '  Codex can call agent-indicator on state transitions via its notify key.\n'
    if ! ask_yn "Patch ~/.codex/config.toml?" "y"; then
        skip "codex: skipped"
        return
    fi
    local codex_config="$codex_dir/config.toml"
    python3 "$SCRIPT_DIR/config/codex_config.py" patch "$codex_config" "$SCRIPT_DIR"
    ok "codex config patched"
}

setup_opencode() {
    header "8. OpenCode Integration"
    local opencode_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    if ! command -v opencode >/dev/null 2>&1 && [ ! -d "$opencode_cfg_dir" ]; then
        skip "opencode: not detected"
        return
    fi
    printf '  OpenCode can call agent-indicator via a plugin.\n'
    if ! ask_yn "Install OpenCode plugin?" "y"; then
        skip "opencode: skipped"
        return
    fi
    local plugins_dir="$opencode_cfg_dir/plugins"
    local plugin_name="opencode-agent-indicator.js"
    mkdir -p "$plugins_dir"
    cp "$SCRIPT_DIR/plugins/$plugin_name" "$plugins_dir/$plugin_name"
    ok "opencode plugin installed to $plugins_dir/$plugin_name"
}

setup_test() {
    header "9. Test"
    if ! ask_yn "Run a quick test of enabled backends?" "y"; then
        skip "test: skipped"
        return
    fi
    printf '\n  Testing needs-input...\n'
    if "$SCRIPT_DIR/agent-state.sh" --state needs-input 2>/dev/null; then
        ok "needs-input fired"
    else
        warn "needs-input failed"
    fi
    sleep 1
    printf '  Testing done state...\n'
    if "$SCRIPT_DIR/agent-state.sh" --state "done" 2>/dev/null; then
        ok "done fired"
    else
        warn "done failed"
    fi
    sleep 1
    printf '  Resetting (off)...\n'
    if "$SCRIPT_DIR/agent-state.sh" --state off 2>/dev/null; then
        ok "off fired"
    else
        warn "off failed"
    fi
}

setup_summary() {
    header "Setup Complete"
    local config_path
    config_path=$(python3 "$CONFIG_PY" --config-path 2>/dev/null || echo "$HOME/.config/agent-indicator/config.json")
    printf '  Config: %s%s%s\n' "$CYAN" "$config_path" "$RESET"

    local claude_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    local codex_config="$HOME/.codex/config.toml"
    local opencode_plugin="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/opencode-agent-indicator.js"
    local has_integrations=false

    if [ -f "$claude_settings" ] && grep -q "agent-indicator" "$claude_settings" 2>/dev/null; then
        has_integrations=true
    fi
    if [ -f "$codex_config" ] && grep -q "agent-indicator" "$codex_config" 2>/dev/null; then
        has_integrations=true
    fi
    if [ -f "$opencode_plugin" ]; then
        has_integrations=true
    fi

    if [ "$has_integrations" = true ]; then
        printf '\n  Integrations installed:\n'
        if [ -f "$claude_settings" ] && grep -q "agent-indicator" "$claude_settings" 2>/dev/null; then
            ok "Claude hooks -> $claude_settings"
        fi
        if [ -f "$codex_config" ] && grep -q "agent-indicator" "$codex_config" 2>/dev/null; then
            ok "Codex notify -> $codex_config"
        fi
        if [ -f "$opencode_plugin" ]; then
            ok "OpenCode plugin -> $opencode_plugin"
        fi
    fi

    printf '\n  Edit config: %s\n' "$config_path"
    printf '  Re-run setup: %s\n' "$SCRIPT_DIR/setup.sh"
    printf '  Test: %s --state needs-input\n\n' "$SCRIPT_DIR/agent-state.sh"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    python3 "$CONFIG_PY" --ensure >/dev/null 2>&1
    setup_platform
    setup_terminal
    setup_tmux
    setup_sound
    setup_desktop
    setup_push
    setup_hooks
    setup_codex
    setup_opencode
    # Fill any missing keys from new defaults into config
    python3 "$CONFIG_PY" --ensure >/dev/null 2>&1
    setup_test
    setup_summary
}

main
