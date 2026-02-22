#!/usr/bin/env python3
"""Config reader/writer for agent-indicator.

Reads ~/.config/agent-indicator/config.json (or XDG_CONFIG_HOME equivalent),
merges with defaults, supports get/set/shell-exports operations.

Usage:
    config.py --get <dotpath>                   # e.g. backends.sound.volume
    config.py --set <dotpath> <value>           # e.g. backends.sound.volume 0.5
    config.py --shell-exports                   # output env vars for bash eval
    config.py --dump                            # print merged config as JSON
"""

import json
import os
import pathlib
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
DEFAULTS_PATH = SCRIPT_DIR / "defaults.json"

def config_dir():
    xdg = os.environ.get("XDG_CONFIG_HOME", "")
    if xdg:
        return pathlib.Path(xdg) / "agent-indicator"
    return pathlib.Path.home() / ".config" / "agent-indicator"

def config_path():
    return config_dir() / "config.json"

def load_defaults():
    try:
        return json.loads(DEFAULTS_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}

def load_user_config():
    p = config_path()
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"Invalid JSON in {p}: {e}", file=sys.stderr)
        sys.exit(1)

def deep_merge(base, override):
    """Merge override into base recursively. Returns new dict."""
    result = dict(base)
    for key, val in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = deep_merge(result[key], val)
        else:
            result[key] = val
    return result

def get_by_path(obj, dotpath):
    """Traverse nested dict by dot-separated path."""
    parts = dotpath.split(".")
    current = obj
    for part in parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            return None
    return current

def set_by_path(obj, dotpath, value):
    """Set a value in nested dict by dot-separated path."""
    parts = dotpath.split(".")
    current = obj
    for part in parts[:-1]:
        if part not in current or not isinstance(current[part], dict):
            current[part] = {}
        current = current[part]
    # Auto-convert types
    if isinstance(value, str):
        if value.lower() in ("true", "false"):
            value = value.lower() == "true"
        else:
            try:
                value = float(value) if "." in value else int(value)
            except ValueError:
                pass
    current[parts[-1]] = value

def save_config(cfg):
    p = config_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")

# ---------------------------------------------------------------------------
# Shell exports: flatten config to AGENT_INDICATOR_* env vars.
# Only exports values not already set in the environment, so explicit
# env vars always win over config file values.
# ---------------------------------------------------------------------------
ENV_MAP = {
    "backends.terminal.enabled":              "AGENT_INDICATOR_TERMINAL",
    "backends.terminal.bg_restore_timeout":   "AGENT_INDICATOR_TERMINAL_BG_RESTORE_TIMEOUT",
    "backends.terminal.bg_needs_input":       "AGENT_INDICATOR_TERMINAL_BG_NEEDS_INPUT",
    "backends.terminal.bg_done":              "AGENT_INDICATOR_TERMINAL_BG_DONE",
    "backends.sound.enabled":             "AGENT_INDICATOR_SOUND",
    "backends.sound.pack":                "AGENT_INDICATOR_SOUND_PACK",
    "backends.sound.volume":              "AGENT_INDICATOR_SOUND_VOLUME",
    "backends.sound.states.needs-input":  "AGENT_INDICATOR_SOUND_STATE_NEEDS_INPUT",
    "backends.sound.states.done":         "AGENT_INDICATOR_SOUND_STATE_DONE",
    "backends.desktop.enabled":           "AGENT_INDICATOR_DESKTOP",
    "backends.desktop.states.needs-input": "AGENT_INDICATOR_DESKTOP_STATE_NEEDS_INPUT",
    "backends.desktop.states.done":       "AGENT_INDICATOR_DESKTOP_STATE_DONE",
    "backends.desktop.title_format":      "AGENT_INDICATOR_DESKTOP_TITLE_FORMAT",
    "backends.desktop.body_format":       "AGENT_INDICATOR_DESKTOP_BODY_FORMAT",
    "backends.push.enabled":              "AGENT_INDICATOR_PUSH",
    "backends.push.service":              "AGENT_INDICATOR_PUSH_SERVICE",
    "backends.push.topic":                "AGENT_INDICATOR_PUSH_TOPIC",
    "backends.push.server":               "AGENT_INDICATOR_PUSH_SERVER",
    "backends.push.token":                "AGENT_INDICATOR_PUSH_TOKEN",
    "backends.push.states.needs-input":   "AGENT_INDICATOR_PUSH_STATE_NEEDS_INPUT",
    "backends.push.states.done":          "AGENT_INDICATOR_PUSH_STATE_DONE",
}

def to_shell_value(val):
    if isinstance(val, bool):
        return "on" if val else "off"
    if val is None:
        return ""
    return str(val)

def shell_exports(cfg):
    lines = []
    for dotpath, env_key in ENV_MAP.items():
        if env_key in os.environ:
            continue
        val = get_by_path(cfg, dotpath)
        if val is not None:
            shell_val = to_shell_value(val)
            # Escape single quotes in values
            shell_val = shell_val.replace("'", "'\\''")
            lines.append(f"export {env_key}='{shell_val}'")
    return "\n".join(lines)

def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    defaults = load_defaults()
    user_cfg = load_user_config()
    merged = deep_merge(defaults, user_cfg)

    cmd = sys.argv[1]

    if cmd == "--get":
        if len(sys.argv) < 3:
            print("Usage: config.py --get <dotpath>", file=sys.stderr)
            sys.exit(1)
        val = get_by_path(merged, sys.argv[2])
        if val is None:
            sys.exit(1)
        if isinstance(val, dict):
            print(json.dumps(val, indent=2))
        elif isinstance(val, bool):
            print("true" if val else "false")
        else:
            print(val)

    elif cmd == "--set":
        if len(sys.argv) < 4:
            print("Usage: config.py --set <dotpath> <value>", file=sys.stderr)
            sys.exit(1)
        set_by_path(user_cfg, sys.argv[2], sys.argv[3])
        save_config(user_cfg)

    elif cmd == "--shell-exports":
        print(shell_exports(merged))

    elif cmd == "--dump":
        print(json.dumps(merged, indent=2))

    elif cmd == "--config-path":
        print(config_path())

    elif cmd == "--ensure":
        # Create config file from defaults if it doesn't exist
        p = config_path()
        if not p.exists():
            save_config({})
            print(f"Created {p}")
        else:
            print(f"Already exists: {p}")

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
