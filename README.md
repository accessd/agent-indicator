# agent-indicator

Visual and audio indicators for AI agent state. Shows running, needs-input, done, and off states through five independent backends: terminal escape sequences, tmux styling, sound alerts, desktop notifications, and push notifications.

Built for Claude Code via hooks, but works with any agent that can call a shell script.

## State mapping

| State | Terminal title | Terminal BG | Tmux border | Sound | Desktop | Push |
|-------|--------------|-------------|-------------|-------|---------|------|
| running | "Running..." | -- | -- | -- | -- | -- |
| needs-input | "Needs Input" | yellow tint | yellow | alert | yes | yes |
| done | "Done" | green tint (3s) | green | chime | yes | yes |
| off | restore | restore | restore | -- | -- | -- |

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
--no-claude           Skip Claude hooks setup
--headless            Non-interactive, reads config from env vars
--setup               Run interactive setup wizard after install
--uninstall           Remove files, config, and Claude hooks
```

The installer copies files to `~/.local/share/agent-indicator` and patches `~/.claude/settings.json` with hooks that map Claude Code events to agent states.

## Setup wizard

Run `./setup.sh` for an interactive walkthrough that detects your platform, configures each backend, patches Claude hooks, and runs a test.

```bash
./setup.sh
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

### Tmux (default: auto)

Sets pane active border color and window status styling. Saves and restores original values on state reset. Auto mode enables this backend only when running inside a tmux session.

Requires `allow-passthrough on` for the terminal backend to reach the outer terminal through tmux:

```
set -g allow-passthrough on
```

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
    "terminal": { "enabled": "on" },
    "tmux": { "enabled": "auto" },
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
| `AGENT_INDICATOR_TMUX` | auto | on when inside tmux |
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

## Claude Code hooks

The installer adds hooks to `~/.claude/settings.json`:

| Hook event | State |
|------------|-------|
| `UserPromptSubmit` | running |
| `PermissionRequest` | needs-input |
| `Stop` | done |

The reference template is in `hooks/claude-hooks.json`.

## Migrating from tmux-agent-indicator

agent-indicator covers the core tmux-agent-indicator functionality (pane borders, window status styling). If you switch:

```bash
cd /path/to/tmux-agent-indicator && ./install.sh --uninstall-claude
cd /path/to/agent-indicator && ./install.sh
```

Both can coexist, but running both means duplicate tmux styling. Disable one tmux backend or the other (`AGENT_INDICATOR_TMUX=off`).

## Project structure

```
agent-indicator/
  agent-state.sh                  # entry point, dispatcher
  config/
    defaults.json                 # default config values
    config.py                     # config reader/writer (python3)
  backends/
    terminal.sh                   # escape sequences (title, bg, bell)
    tmux.sh                       # pane border, window status styling
    sound.sh                      # CESP pack player with no-repeat
    desktop.sh                    # osascript/terminal-notifier, notify-send
    push.sh                       # ntfy, Pushover, Telegram via curl
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
