#!/usr/bin/env bash
# Installer for agent-indicator.
# Works from a local clone or via curl pipe to bash.

set -euo pipefail

SCRIPT_DIR=""
TMP_SOURCE_DIR=""

SCRIPT_SOURCE=""
case "${0:-}" in
    bash|-bash|sh|-sh)
        ;;
    *)
        SCRIPT_SOURCE="${0}"
        ;;
esac

if [ -z "$SCRIPT_SOURCE" ] && [ -n "${BASH_SOURCE+set}" ] && [ "${#BASH_SOURCE[@]}" -gt 0 ]; then
    SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi

if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi

if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/agent-state.sh" ]; then
    INSTALL_REPO="${AGENT_INDICATOR_INSTALL_REPO:-accessd/agent-indicator}"
    INSTALL_REF="${AGENT_INDICATOR_INSTALL_REF:-main}"
    ARCHIVE_URL="https://codeload.github.com/${INSTALL_REPO}/tar.gz/refs/heads/${INSTALL_REF}"

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required for stdin-based installation" >&2
        exit 1
    fi
    if ! command -v tar >/dev/null 2>&1; then
        echo "tar is required for stdin-based installation" >&2
        exit 1
    fi

    TMP_SOURCE_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_SOURCE_DIR"' EXIT
    curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$TMP_SOURCE_DIR"
    SCRIPT_DIR="$(find "$TMP_SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

    if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/agent-state.sh" ]; then
        echo "Failed to fetch installer sources from $ARCHIVE_URL" >&2
        exit 1
    fi
fi

TARGET_DIR="${AGENT_INDICATOR_INSTALL_DIR:-$HOME/.local/share/agent-indicator}"
UNINSTALL_MODE=false
HEADLESS=false
SKIP_SETUP=false

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

Options:
  --target-dir <path>   Install path (default: ~/.local/share/agent-indicator)
  --uninstall           Remove agent-indicator files and hooks
  --headless            Non-interactive install (use env vars for config)
  --skip-setup          Skip interactive setup wizard after install
  -h, --help            Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target-dir)
            [ "$#" -lt 2 ] && usage && exit 1
            TARGET_DIR="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL_MODE=true
            shift
            ;;
        --headless)
            HEADLESS=true
            SKIP_SETUP=true
            shift
            ;;
        --skip-setup)
            SKIP_SETUP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if [ "$UNINSTALL_MODE" = true ]; then
    # Remove hooks from Claude settings
    CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
    if [ -f "$CLAUDE_SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
        python3 - "$CLAUDE_SETTINGS" "$TARGET_DIR" "uninstall" <<'PY'
import json, pathlib, sys
settings_path = pathlib.Path(sys.argv[1])
try:
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)
hooks = settings.get("hooks", {})
for event in list(hooks.keys()):
    entries = hooks.get(event, [])
    cleaned = []
    for entry in entries:
        hook_items = entry.get("hooks", [])
        filtered = [h for h in hook_items if not ("agent-state.sh" in h.get("command", "") and "agent-indicator" in h.get("command", ""))]
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
settings["hooks"] = hooks
settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
PY
        echo "Removed agent-indicator hooks from: $CLAUDE_SETTINGS"
    fi

    # Remove notify line from Codex config.toml (restore original if chained)
    CODEX_CONFIG="$HOME/.codex/config.toml"
    if [ -f "$CODEX_CONFIG" ] && command -v python3 >/dev/null 2>&1; then
        python3 "$TARGET_DIR/config/codex_config.py" unpatch "$CODEX_CONFIG" "$TARGET_DIR"
        echo "Removed agent-indicator notify from: $CODEX_CONFIG"
    fi

    # Remove OpenCode plugin
    OPENCODE_PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins"
    OPENCODE_PLUGIN_NAME="opencode-agent-indicator.js"
    if [ -f "$OPENCODE_PLUGINS_DIR/$OPENCODE_PLUGIN_NAME" ]; then
        rm -f "$OPENCODE_PLUGINS_DIR/$OPENCODE_PLUGIN_NAME"
        echo "Removed OpenCode plugin from: $OPENCODE_PLUGINS_DIR"
    fi

    # Remove installed files
    if [ -d "$TARGET_DIR" ]; then
        rm -rf "$TARGET_DIR"
        echo "Removed: $TARGET_DIR"
    fi

    # Remove config
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agent-indicator"
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        echo "Removed: $CONFIG_DIR"
    fi

    echo "Uninstall complete."
    exit 0
fi

# ---------------------------------------------------------------------------
# Install files
# ---------------------------------------------------------------------------
mkdir -p "$TARGET_DIR/backends" "$TARGET_DIR/hooks" "$TARGET_DIR/lib" "$TARGET_DIR/config" "$TARGET_DIR/packs" "$TARGET_DIR/adapters" "$TARGET_DIR/plugins"

cp "$SCRIPT_DIR/agent-state.sh" "$TARGET_DIR/"
cp "$SCRIPT_DIR/backends/"*.sh "$TARGET_DIR/backends/"
cp "$SCRIPT_DIR/hooks/claude-hooks.json" "$TARGET_DIR/hooks/"
cp "$SCRIPT_DIR/adapters/"*.sh "$TARGET_DIR/adapters/"
chmod +x "$TARGET_DIR/adapters/"*.sh
cp "$SCRIPT_DIR/lib/"*.sh "$TARGET_DIR/lib/"
cp "$SCRIPT_DIR/config/defaults.json" "$TARGET_DIR/config/"
cp "$SCRIPT_DIR/config/config.py" "$TARGET_DIR/config/"
cp "$SCRIPT_DIR/config/codex_config.py" "$TARGET_DIR/config/"

# Copy packs
if [ -d "$SCRIPT_DIR/packs" ]; then
    cp -r "$SCRIPT_DIR/packs/"* "$TARGET_DIR/packs/" 2>/dev/null || true
fi

# Copy plugins
if [ -d "$SCRIPT_DIR/plugins" ]; then
    cp "$SCRIPT_DIR/plugins/"*.js "$TARGET_DIR/plugins/" 2>/dev/null || true
fi

if [ -f "$SCRIPT_DIR/README.md" ]; then
    cp "$SCRIPT_DIR/README.md" "$TARGET_DIR/"
fi
if [ -f "$SCRIPT_DIR/setup.sh" ]; then
    cp "$SCRIPT_DIR/setup.sh" "$TARGET_DIR/"
    chmod +x "$TARGET_DIR/setup.sh"
fi

chmod +x "$TARGET_DIR/agent-state.sh"

echo "Installed agent-indicator to: $TARGET_DIR"

# ---------------------------------------------------------------------------
# Headless config from env vars
# ---------------------------------------------------------------------------
if [ "$HEADLESS" = true ] && command -v python3 >/dev/null 2>&1; then
    CONFIG_PY="$TARGET_DIR/config/config.py"
    # Write config values from env vars if set
    _set_if() {
        local env_var="$1" config_path="$2"
        local val="${!env_var:-}"
        if [ -n "$val" ]; then
            python3 "$CONFIG_PY" --set "$config_path" "$val"
        fi
    }
    _set_if AGENT_INDICATOR_TERMINAL "backends.terminal.enabled"
    _set_if AGENT_INDICATOR_TERMINAL_BG_RESTORE_TIMEOUT "backends.terminal.bg_restore_timeout"
    _set_if AGENT_INDICATOR_TERMINAL_BG_NEEDS_INPUT "backends.terminal.bg_needs_input"
    _set_if AGENT_INDICATOR_TERMINAL_BG_DONE "backends.terminal.bg_done"
    _set_if AGENT_INDICATOR_SOUND "backends.sound.enabled"
    _set_if AGENT_INDICATOR_SOUND_PACK "backends.sound.pack"
    _set_if AGENT_INDICATOR_SOUND_VOLUME "backends.sound.volume"
    _set_if AGENT_INDICATOR_DESKTOP "backends.desktop.enabled"
    _set_if AGENT_INDICATOR_PUSH "backends.push.enabled"
    _set_if AGENT_INDICATOR_PUSH_SERVICE "backends.push.service"
    _set_if AGENT_INDICATOR_PUSH_TOPIC "backends.push.topic"
    _set_if AGENT_INDICATOR_PUSH_SERVER "backends.push.server"
    _set_if AGENT_INDICATOR_PUSH_TOKEN "backends.push.token"
    echo "Config written from environment variables."
fi

# ---------------------------------------------------------------------------
# Post-install: run setup wizard
# ---------------------------------------------------------------------------
if [ "$SKIP_SETUP" != true ] && [ -f "$TARGET_DIR/setup.sh" ]; then
    echo ""
    exec "$TARGET_DIR/setup.sh"
fi

cat <<EOF

Run the setup wizard to configure backends and agent integrations:
  $TARGET_DIR/setup.sh

Env var overrides still work:
  export AGENT_INDICATOR_TERMINAL=on   # tab title, bg color, notifications (default: on)
  export AGENT_INDICATOR_SOUND=on      # audio alerts (default: off)
  export AGENT_INDICATOR_DESKTOP=on    # desktop notifications (default: off)
  export AGENT_INDICATOR_PUSH=on       # push notifications (default: off)

For tmux styling, use tmux-agent-indicator:
  https://github.com/accessd/tmux-agent-indicator
EOF
