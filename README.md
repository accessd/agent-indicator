# agent-indicator

Visual and audio indicators for AI agent state. Shows running, needs-input, done, and off states through four backends: terminal escape sequences, sound alerts, desktop notifications, and push notifications.

Built for Claude Code, Codex, and OpenCode. Works with any agent that can call a shell script.

## State mapping

| State | Terminal title | Terminal BG | Sound | Desktop | Push |
|-------|--------------|-------------|-------|---------|------|
| running | "Running..." | -- | -- | -- | -- |
| needs-input | "Needs Input" | yellow tint | alert | yes | yes |
| done | "Done" | green tint (configurable timeout) | chime | yes | yes |
| off | restore | restore | -- | -- | -- |

## Install

One-liner:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/accessd/agent-indicator/main/install.sh)
```

Or clone and run:

```bash
git clone https://github.com/accessd/agent-indicator.git
cd agent-indicator
./install.sh
```

Installer flags:

```
--target-dir <path>   Install location (default: ~/.local/share/agent-indicator)
--skip-setup          Skip the interactive setup wizard after install
--headless            Non-interactive, reads config from env vars (implies --skip-setup)
--uninstall           Remove files, config, and all integrations
```

The installer copies files to `~/.local/share/agent-indicator` and launches the setup wizard. The wizard detects your platform, walks through each backend, configures agent integrations (Claude, Codex, OpenCode), and runs a test.

To reconfigure later:

```bash
~/.local/share/agent-indicator/setup.sh
```

## Usage

```bash
./agent-state.sh --state running
./agent-state.sh --state needs-input
./agent-state.sh --state done
./agent-state.sh --state off
```

Options:

```
--state <running|needs-input|done|off>   Required
--agent <name>                           Agent name for tracking (default: claude)
--tty /dev/ttysXXX                       Target specific terminal
```

## Backends

### Terminal (default: on)

Sets tab title, background color tint, terminal-level notifications, and bell via escape sequences. Works with most modern terminals. Wraps sequences in tmux passthrough when inside tmux.

| Terminal | Title | BG color | Notification |
|----------|-------|----------|-------------|
| iTerm2 | OSC 2 | OSC 11 | OSC 9 + dock bounce |
| WezTerm | OSC 2 | OSC 11 | OSC 9 |
| Kitty | OSC 2 | OSC 11 | OSC 777 |
| Ghostty | OSC 2 | OSC 11 | OSC 9 |
| Terminal.app | OSC 2 | n/a | n/a |
| Windows Terminal | OSC 2 | OSC 11 | OSC 9 |
| GNOME/VTE | OSC 2 | OSC 11 | OSC 777 |
| Alacritty | OSC 2 | OSC 11 | OSC 9 |

Terminal-specific config:

| Env var | Default | Description |
|---------|---------|-------------|
| `AGENT_INDICATOR_TERMINAL_BG_NEEDS_INPUT` | `3b3000` | Hex color for needs-input background (no # prefix) |
| `AGENT_INDICATOR_TERMINAL_BG_DONE` | `002b00` | Hex color for done background (no # prefix) |
| `AGENT_INDICATOR_TERMINAL_BG_RESTORE_TIMEOUT` | `3` | Seconds before done bg resets. Set to `0` to keep done bg until next state change |

### Tmux

For tmux pane borders, window status styling, and animation, use the standalone [tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator) plugin. The setup wizard can install it for you.

### Sound (default: off)

Plays audio alerts on needs-input and done states using CESP sound packs. Picks a random sound from the pack with no-repeat logic.

Player fallback chain: `afplay` (macOS) -> `paplay` -> `aplay` -> `play` (SoX).

Config options:

| Env var | Description |
|---------|-------------|
| `AGENT_INDICATOR_SOUND_PACK` | Pack name (default: "default") |
| `AGENT_INDICATOR_SOUND_VOLUME` | 0.0 to 1.0 |
| `AGENT_INDICATOR_SOUND_STATE_NEEDS_INPUT` | on/off per state |
| `AGENT_INDICATOR_SOUND_STATE_DONE` | on/off per state |
| `AGENT_INDICATOR_SOUND_NEEDS_INPUT` | Override: path to specific file |
| `AGENT_INDICATOR_SOUND_DONE` | Override: path to specific file |
| `AGENT_INDICATOR_SOUND_COMMAND` | Override: custom command (receives state as arg) |

### Desktop notifications (default: off)

OS-level notification popups, separate from terminal-level notifications.

- macOS: `terminal-notifier` if available, falls back to `osascript`
- Linux/WSL: `notify-send` (libnotify)

Supports format templates with `{agent}` and `{state}` placeholders:

| Env var | Default |
|---------|---------|
| `AGENT_INDICATOR_DESKTOP_TITLE_FORMAT` | `[{agent}] {state}` |
| `AGENT_INDICATOR_DESKTOP_BODY_FORMAT` | `{agent} is {state}` |
| `AGENT_INDICATOR_DESKTOP_STATE_NEEDS_INPUT` | on |
| `AGENT_INDICATOR_DESKTOP_STATE_DONE` | on |

### Push notifications (default: off)

Sends HTTP notifications to your phone via one of three services. Requires `curl`.

**ntfy** (easiest, no signup for public topics):

```bash
AGENT_INDICATOR_PUSH=on
AGENT_INDICATOR_PUSH_SERVICE=ntfy
AGENT_INDICATOR_PUSH_TOPIC=my-agent-alerts
AGENT_INDICATOR_PUSH_SERVER=https://ntfy.sh     # optional, this is the default
AGENT_INDICATOR_PUSH_TOKEN=                      # optional, for private topics
```

**Pushover**:

```bash
AGENT_INDICATOR_PUSH=on
AGENT_INDICATOR_PUSH_SERVICE=pushover
AGENT_INDICATOR_PUSH_TOKEN=<api-token>
AGENT_INDICATOR_PUSH_TOPIC=<user-key>
```

**Telegram**:

```bash
AGENT_INDICATOR_PUSH=on
AGENT_INDICATOR_PUSH_SERVICE=telegram
AGENT_INDICATOR_PUSH_TOKEN=<bot-token>
AGENT_INDICATOR_PUSH_TOPIC=<chat-id>
```

Per-state control: `AGENT_INDICATOR_PUSH_STATE_NEEDS_INPUT` and `AGENT_INDICATOR_PUSH_STATE_DONE` (on/off).

## Configuration

Two ways to configure:

1. **Config file**: `~/.config/agent-indicator/config.json` (respects `XDG_CONFIG_HOME`)
2. **Environment variables**: `AGENT_INDICATOR_*`

Priority: env var > config.json > defaults.json

### Config file

Created by the setup wizard or manually. Example:

```json
{
  "backends": {
    "terminal": {
      "enabled": "on",
      "bg_restore_timeout": 3,
      "bg_needs_input": "3b3000",
      "bg_done": "002b00"
    },
    "sound": { "enabled": "on", "volume": 0.7, "pack": "default" },
    "desktop": { "enabled": "on" },
    "push": { "enabled": "off" }
  }
}
```

### config.py subcommands

```bash
python3 config/config.py --shell-exports           # env var exports for bash eval
python3 config/config.py --get backends.sound.volume  # read a value by dotpath
python3 config/config.py --set backends.sound.volume 0.8  # write a value
python3 config/config.py --dump                     # print merged config as JSON
python3 config/config.py --config-path              # print config file location
python3 config/config.py --ensure                   # create config file if missing
```

### Backend toggles

| Env var | Default | Notes |
|---------|---------|-------|
| `AGENT_INDICATOR_TERMINAL` | on | |
| `AGENT_INDICATOR_SOUND` | off | |
| `AGENT_INDICATOR_DESKTOP` | off | |
| `AGENT_INDICATOR_PUSH` | off | |

## Sound packs

Sound packs use CESP v1.0 format. Each pack is a directory under `packs/` containing an `openpeon.json` manifest.

Manifest structure:

```json
{
  "cesp_version": "1.0",
  "name": "My Pack",
  "sounds": {
    "needs-input": [
      { "system": "Funk" },
      { "file": "alert.wav" }
    ],
    "done": [
      { "system": "Glass" },
      { "file": "chime.ogg" }
    ]
  }
}
```

Entries can reference system sounds by name (`{ "system": "Funk" }`) or bundled audio files relative to the pack directory (`{ "file": "alert.wav" }`). The player picks randomly from available sounds per state.

To use a custom pack:

```bash
AGENT_INDICATOR_SOUND_PACK=my-pack ./agent-state.sh --state needs-input
```

Or set it in config:

```bash
python3 config/config.py --set backends.sound.pack my-pack
```

## Agent integrations

The setup wizard auto-detects which agents are present and configures each one. If an agent is not found, its integration is skipped. Re-run setup after adding a new agent.

### Claude Code

Integrates via hooks in `~/.claude/settings.json`.

| Hook event | State |
|------------|-------|
| `UserPromptSubmit` | running |
| `PermissionRequest` | needs-input |
| `Stop` | done |

The reference template is in `hooks/claude-hooks.json`. Detection: checks for `claude` command or `~/.claude/` directory.

### Codex

Integrates via the `notify` key in `~/.codex/config.toml`, which points to an adapter script that maps Codex events to states.

```toml
notify = ["~/.local/share/agent-indicator/adapters/codex-notify.sh"]
```

If `config.toml` already has a `notify` script (e.g. from tmux-agent-indicator), setup generates a chain wrapper that calls both scripts instead of replacing the existing one. Uninstall restores the original.

| Codex event | State |
|-------------|-------|
| `start`, `session-start`, `turn-start`, `working` | running |
| `permission*`, `approve*`, `needs-input`, `input-required`, `ask-user` | needs-input |
| `agent-turn-complete`, `complete`, `done`, `stop`, `error`, `fail*` | done |

Detection: checks for `codex` command or `~/.codex/` directory.

### OpenCode

Integrates via a JS plugin copied to `~/.config/opencode/plugins/opencode-agent-indicator.js`.

| OpenCode event | State |
|----------------|-------|
| `session.status` (busy) | running |
| `permission.updated`, `permission.asked`, `permission.ask`, `tool.execute.before` (question) | needs-input |
| `session.idle`, `session.error` | done |

The plugin tracks state internally and avoids redundant calls. A 2-second guard prevents race conditions between idle and busy events.

Detection: checks for `opencode` command or `~/.config/opencode/` directory.

Manual install (if not using the installer):

```bash
cp plugins/opencode-agent-indicator.js ~/.config/opencode/plugins/
```

Override the install path via `AGENT_INDICATOR_DIR` env var if agent-indicator is not at the default location.

## Project structure

```
agent-indicator/
  agent-state.sh                  # entry point, dispatcher
  config/
    defaults.json                 # default config values
    config.py                     # config reader/writer (python3)
    codex_config.py               # Codex config.toml patcher (chain-aware)
  backends/
    terminal.sh                   # escape sequences (title, bg, bell)
    sound.sh                      # CESP pack player with no-repeat
    desktop.sh                    # osascript/terminal-notifier, notify-send
    push.sh                       # ntfy, Pushover, Telegram via curl
  adapters/
    codex-notify.sh               # Codex event-to-state mapper
  plugins/
    opencode-agent-indicator.js   # OpenCode plugin
  packs/
    default/openpeon.json         # default sound pack (system sounds)
  lib/
    platform.sh                   # OS/tool detection
    log.sh                        # stderr logger
  hooks/
    claude-hooks.json             # reference hook template
  setup.sh                        # interactive setup wizard
  install.sh                      # installer
```

## License

MIT
