# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Shell + Python project (bash with python3 for config). No build step, no tests. All shell scripts use `set -euo pipefail`.

Provides visual/audio indicators for AI agent state (running, needs-input, done, off) across four backends: terminal, sound, desktop notifications, and push notifications. Integrates with Claude Code via hooks. For tmux styling, use the separate tmux-agent-indicator plugin.

## Manual testing

```bash
./agent-state.sh --state running
./agent-state.sh --state needs-input
./agent-state.sh --state done
./agent-state.sh --state off
```

Use `--tty /dev/ttysXXX` to target a specific terminal. Use `--agent <name>` for desktop/push tracking.

Enable backends for testing (edit config.json or use config.py):
```bash
python3 config/config.py --set backends.sound.enabled true
python3 config/config.py --set backends.desktop.enabled true
./agent-state.sh --state needs-input
```

## Architecture

```
agent-state.sh                    # entry point, dispatcher
├── config/
│   ├── defaults.json             # default config values
│   ├── config.py                 # config reader/writer (python3)
│   └── codex_config.py           # Codex config.toml patcher (chain-aware)
├── backends/
│   ├── terminal.sh               # escape sequences (title, bg, bell)
│   ├── sound.sh                  # CESP pack player with no-repeat
│   ├── desktop.sh                # macOS osascript/terminal-notifier, Linux notify-send
│   └── push.sh                   # ntfy, Pushover, Telegram via curl
├── adapters/
│   └── codex-notify.sh           # Codex event-to-state mapper
├── packs/
│   └── default/openpeon.json     # default sound pack manifest (system sounds)
├── lib/
│   ├── platform.sh               # OS/tool detection
│   └── log.sh                    # stderr logger
├── hooks/
│   └── claude-hooks.json         # reference hook template
├── setup.sh                      # interactive setup wizard
└── install.sh                    # installer (local or curl-pipe)
```

### Dispatcher flow

`agent-state.sh` is the entry point. It:
1. Loads config via `config.py --shell-exports` (if python3 available). This converts `config.json` to env vars. Config.json is the single source of truth.
2. Sources `lib/log.sh` and `lib/platform.sh`
3. Parses args and resolves the target TTY
4. Writes state to a temp file keyed by TTY slug
5. Dispatches to each enabled backend. Each backend is independent; failures are logged but do not block other backends.

### Config system

Config file: `~/.config/agent-indicator/config.json` (respects `XDG_CONFIG_HOME`).

`config/config.py` handles read/merge/write:
- `--shell-exports`: outputs env var exports for bash eval (always from config file)
- `--get <dotpath>`: read a value (e.g. `backends.sound.volume`)
- `--set <dotpath> <value>`: write a value
- `--dump`: print merged config as JSON
- `--config-path`: print config file location
- `--ensure`: create/update config file with all defaults merged in

Priority: config.json > defaults.json

### Backend interface

Every backend exposes one public function:
```bash
<backend>_apply <state> [<tty>] [<agent>]
```

- `terminal_apply <state> <tty> <state_file>` -- OSC 2 title, OSC 11 bg color, OSC 9/777 notifications, bell. Wraps in tmux passthrough when inside tmux.
- `sound_apply <state>` -- loads CESP pack manifest, picks sound (no-repeat), plays via afplay/paplay/aplay/play chain. Supports volume control.
- `desktop_apply <state> <agent>` -- macOS: osascript or terminal-notifier. Linux: notify-send. Configurable title/body format templates.
- `push_apply <state> <agent>` -- HTTP POST via curl to ntfy, Pushover, or Telegram.

### Backend activation

Controlled by config.json:
- `backends.terminal.enabled` (default: on)
- `backends.sound.enabled` (default: off)
- `backends.desktop.enabled` (default: off)
- `backends.push.enabled` (default: off)

### Sound packs

Sound packs use CESP v1.0 format. Each pack has an `openpeon.json` manifest listing sound entries per state. Entries can be `{ "file": "path" }` for bundled audio or `{ "system": "Name" }` for system sounds. The player picks randomly with no-repeat logic.

## Installer

`install.sh` copies files to `~/.local/share/agent-indicator` and launches the setup wizard. Works two ways:
- From a local clone (detects `agent-state.sh` next to itself)
- Via curl pipe to bash (downloads tarball to temp dir)

Flags:
- `--skip-setup`: skip the interactive setup wizard
- `--uninstall`: removes files, config, and all integrations

Agent integrations (Claude hooks, Codex config, OpenCode plugin) are configured by `setup.sh`, not the installer itself.

## Setup wizard

`setup.sh` is an interactive TUI that:
1. Detects platform and available tools
2. Walks through each backend (terminal, sound, desktop, push) and offers tmux-agent-indicator install
3. Writes config.json
4. Patches Claude hooks, Codex config.toml, and OpenCode plugin
5. Offers a test step

## Hooks template

`hooks/claude-hooks.json` is the reference template. Hook events: `UserPromptSubmit` -> running, `PermissionRequest` -> needs-input, `Stop` -> done.
