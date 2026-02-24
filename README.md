# agent-indicator

Visual and audio indicators for AI agent state. Shows running, needs-input, done, and off states through four backends: terminal escape sequences, sound alerts, desktop notifications, and push notifications.


https://github.com/user-attachments/assets/42aeb041-8ea9-407d-8d4e-26616b1b8cb9
<img width="2642" height="1492" alt="Screenshot 2026-02-24 at 21 03 34" src="https://github.com/user-attachments/assets/8d17fd75-d976-4e3d-88d9-be681a8e0e72" />


Built for Claude Code, Codex, and OpenCode. Works with any agent that can call a shell script.

## How it works

Your AI agent triggers a hook on state change. The hook calls `agent-state.sh`, which dispatches to whichever backends you enabled.

Each state triggers different actions depending on the backend:

| State | Terminal title | Terminal BG | Sound | Desktop | Push |
|-------|--------------|-------------|-------|---------|------|
| running | "Running..." | restore | -- | -- | -- |
| needs-input | "Needs Input" | yellow tint | alert | yes | yes |
| done | "Done" | green tint (configurable timeout) | chime | yes | yes |
| off | restore | restore | -- | -- | -- |

## Prerequisites

- bash
- python3 (config system and setup wizard)
- curl + tar (remote install only)

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
--uninstall           Remove files, config, and all integrations
```

The installer copies files to `~/.local/share/agent-indicator` and launches the setup wizard. The wizard detects your platform, walks through each backend, configures agent integrations (Claude, Codex, OpenCode), and runs a test.

To reconfigure later:

```bash
~/.local/share/agent-indicator/setup.sh
```

## Uninstall

```bash
~/.local/share/agent-indicator/install.sh --uninstall
```

This removes:
- Installed files (`~/.local/share/agent-indicator`)
- Config directory (`~/.config/agent-indicator`)
- Claude Code hooks from `~/.claude/settings.json`
- Codex notify entry from `~/.codex/config.toml` (restores original if chained)
- OpenCode plugin from `~/.config/opencode/plugins/`

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
-h, --help                               Show help
```

## Backends

### Terminal (default: on)

Sets tab title, background color tint, bell, and terminal-level notifications via escape sequences. Works with most modern terminals. Wraps sequences in tmux passthrough when inside tmux.

On needs-input, the terminal backend also fires a bell character (`\a`) and, on iTerm2, requests dock attention via `OSC 1337;RequestAttention`.

| Terminal | Title | BG color | Notification |
|----------|-------|----------|-------------|
| iTerm2 | OSC 2 | OSC 11 | OSC 9, OSC 1337 (dock bounce) |
| WezTerm | OSC 2 | OSC 11 | OSC 9 |
| Kitty | OSC 2 | OSC 11 | OSC 777 |
| Ghostty | OSC 2 | OSC 11 | OSC 9 |
| Terminal.app | OSC 2 | n/a | n/a |
| Windows Terminal | OSC 2 | OSC 11 | OSC 9 |
| GNOME/VTE | OSC 2 | OSC 11 | OSC 777 |
| Alacritty | OSC 2 | OSC 11 | OSC 9 |

Terminal config keys:

| Key | Default | Description |
|-----|---------|-------------|
| `backends.terminal.bg_needs_input` | `3b3000` | Hex color for needs-input background (no # prefix) |
| `backends.terminal.bg_done` | `002b00` | Hex color for done background (no # prefix) |
| `backends.terminal.bg_restore_timeout` | `3` | Seconds before done bg resets. Set to `0` to keep done bg until next state change |

### Tmux

For tmux pane borders, window status styling, and animation, use the standalone [tmux-agent-indicator](https://github.com/accessd/tmux-agent-indicator) plugin. The setup wizard can install it for you.

### Sound (default: off)

Plays audio alerts on needs-input and done states using CESP sound packs. Picks a random sound from the pack with no-repeat logic.

Player fallback chain: `afplay` (macOS) -> `paplay` -> `aplay` -> `play` (SoX).

Config keys:

| Key | Default | Description |
|-----|---------|-------------|
| `backends.sound.pack` | `default` | Pack name |
| `backends.sound.volume` | `0.5` | 0.0 to 1.0 |
| `backends.sound.command` | `""` | Override: custom command (receives state as arg) |
| `backends.sound.states.needs-input` | `true` | Play on needs-input |
| `backends.sound.states.done` | `true` | Play on done |
| `backends.sound.overrides.needs-input` | `""` | Override: path to specific file |
| `backends.sound.overrides.done` | `""` | Override: path to specific file |

### Desktop notifications (default: off)

OS-level notification popups, separate from terminal-level notifications.

- macOS: `terminal-notifier` if available, falls back to `osascript`
- Linux/WSL: `notify-send` (libnotify)

Supports format templates with `{agent}` and `{state}` placeholders:

| Key | Default |
|-----|---------|
| `backends.desktop.title_format` | `[{agent}] {state}` |
| `backends.desktop.body_format` | `{agent} is {state}` |
| `backends.desktop.states.needs-input` | `true` |
| `backends.desktop.states.done` | `true` |

### Push notifications (default: off)

Sends HTTP notifications to your phone via one of three services. Requires `curl`.

| Service | `service` value | `token` | `topic` | `server` |
|---------|----------------|---------|---------|----------|
| ntfy | `ntfy` | access token (optional) | topic name | `https://ntfy.sh` (default) |
| Pushover | `pushover` | API token | user key | -- |
| Telegram | `telegram` | bot token | chat ID | -- |

Example (ntfy):

```bash
python3 config/config.py --set backends.push.enabled true
python3 config/config.py --set backends.push.service ntfy
python3 config/config.py --set backends.push.topic my-agent-alerts
```

Example (Pushover):

```bash
python3 config/config.py --set backends.push.service pushover
python3 config/config.py --set backends.push.token <api-token>
python3 config/config.py --set backends.push.topic <user-key>
```

Example (Telegram):

```bash
python3 config/config.py --set backends.push.service telegram
python3 config/config.py --set backends.push.token <bot-token>
python3 config/config.py --set backends.push.topic <chat-id>
```

Per-state control: `backends.push.states.needs-input` and `backends.push.states.done` (true/false).

## Configuration

All settings live in `~/.config/agent-indicator/config.json` (respects `XDG_CONFIG_HOME`).

Created by the setup wizard or `install.sh`. Example:

```json
{
  "log_level": "warn",
  "backends": {
    "terminal": {
      "enabled": "on",
      "bg_restore_timeout": 3,
      "bg_needs_input": "3b3000",
      "bg_done": "002b00"
    },
    "sound": { "enabled": "off", "volume": 0.5, "pack": "default" },
    "desktop": { "enabled": "off" },
    "push": { "enabled": "off" }
  }
}
```

### config.py subcommands

```bash
python3 config/config.py --get backends.sound.volume  # read a value by dotpath
python3 config/config.py --set backends.sound.volume 0.8  # write a value
python3 config/config.py --dump                     # print merged config as JSON
python3 config/config.py --config-path              # print config file location
python3 config/config.py --ensure                   # create/update config with all defaults
```

### Backend toggles

Accepted enabled values: `on`, `true`, `yes`, `1` (and their inverses for off).

| Key | Default |
|-----|---------|
| `backends.terminal.enabled` | `on` |
| `backends.sound.enabled` | `off` |
| `backends.desktop.enabled` | `off` |
| `backends.push.enabled` | `off` |

### Logging and debug

Set `log_level` in config.json or via environment variables. Levels: `quiet`, `error`, `warn` (default), `info`, `debug`.

| Env var | Description |
|---------|-------------|
| `AGENT_INDICATOR_LOG_LEVEL` | Override log level (e.g. `debug`) |
| `AGENT_INDICATOR_QUIET` | Set to `1` to suppress all log output |

### Environment variables

| Env var | Description |
|---------|-------------|
| `AGENT_INDICATOR_DIR` | Override install path used in hooks |
| `AGENT_INDICATOR_INSTALL_DIR` | Alternative to `--target-dir` flag for installer |
| `AGENT_INDICATOR_INSTALL_REPO` | Point curl installer at a fork (default: `accessd/agent-indicator`) |
| `AGENT_INDICATOR_INSTALL_REF` | Point curl installer at a branch (default: `main`) |

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

## Troubleshooting

**Background color not changing**: Terminal.app does not support OSC 11. Use iTerm2, Kitty, WezTerm, Ghostty, or another terminal from the compatibility table.

**Sound not playing**: Check that an audio player is available. Run `which afplay paplay aplay play` to see what you have. At least one is required for the sound backend.

**Hooks not firing in Claude Code**: Verify that `~/.claude/settings.json` contains agent-indicator hook entries. Re-run the setup wizard or check the reference template in `hooks/claude-hooks.json`.

**python3 not found**: The config system and setup wizard require python3. Install it via your package manager. Without python3, `agent-state.sh` still runs but uses hardcoded defaults.

**Debugging**: Set `log_level` to `debug` in config.json or run with `AGENT_INDICATOR_LOG_LEVEL=debug` to see detailed output on stderr.

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
