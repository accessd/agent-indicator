# agent-indicator

Unified agent state indicator. Shows AI agent state (running, needs-input, done) through multiple backends:

- **Terminal**: tab title, background color tint, desktop notifications, bell
- **Tmux**: pane border, window status styling
- **Sound**: audio alerts on state changes

Auto-detects the environment and activates the right backends.

## State mapping

| State | Title | BG color | Border | Notification | Sound |
|-------|-------|----------|--------|-------------|-------|
| running | "Running..." | - | - | - | - |
| needs-input | "Needs Input" | yellow tint | yellow | yes + bell | alert |
| done | "Done" | green tint (3s) | green | yes | chime |
| off | restore | restore | restore | - | - |

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

Options:

```
--target-dir <path>   Install path (default: ~/.local/share/agent-indicator)
--no-claude           Skip Claude hooks setup
--uninstall-claude    Remove hooks from Claude settings
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
--agent <name>                           Agent name for tmux tracking (default: claude)
--tty /dev/ttysXXX                       Target specific terminal
```

## Backends

### Terminal (default: on)

Uses native escape sequences. Works with iTerm2, WezTerm, Kitty, Ghostty, Terminal.app, Windows Terminal, GNOME/VTE, Alacritty. Wraps in tmux passthrough when inside tmux.

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

### Tmux (default: auto, on when inside tmux)

Sets pane active border color and window status styling. Saves and restores original values on state reset.

Requires tmux with `allow-passthrough on` for terminal backend to reach the outer terminal:

```
set -g allow-passthrough on
```

### Sound (default: off)

Plays audio on needs-input and done states. On macOS uses system sounds (Funk, Glass) via `afplay`. On Linux tries `paplay`, `aplay`, or `play`.

## Configuration

All via environment variables:

```bash
# Backend toggles
export AGENT_INDICATOR_TERMINAL=on    # default: on
export AGENT_INDICATOR_TMUX=on        # default: auto (on if inside tmux)
export AGENT_INDICATOR_SOUND=on       # default: off

# Custom sounds
export AGENT_INDICATOR_SOUND_NEEDS_INPUT=/path/to/alert.wav
export AGENT_INDICATOR_SOUND_DONE=/path/to/chime.wav

# Or a custom sound command (receives state as arg)
export AGENT_INDICATOR_SOUND_COMMAND="my-sound-player"

# Override install directory in hooks
export AGENT_INDICATOR_DIR=/path/to/agent-indicator
```

## Claude Code hooks

The installer adds hooks to `~/.claude/settings.json`:

- `UserPromptSubmit` -> `--state running`
- `PermissionRequest` -> `--state needs-input`
- `Stop` -> `--state done`

## Migrating from tmux-agent-indicator

agent-indicator includes a tmux backend that covers the core tmux-agent-indicator functionality (pane borders, window status styling). If you switch, remove the old hooks:

```bash
# Remove tmux-agent-indicator hooks
cd /path/to/tmux-agent-indicator
./install.sh --uninstall-claude

# Install agent-indicator
cd /path/to/agent-indicator
./install.sh
```

Both can coexist, but running both means duplicate tmux styling. Pick one for tmux, or disable the tmux backend here (`AGENT_INDICATOR_TMUX=off`) and keep tmux-agent-indicator for tmux-only features (animation, status bar segment).

## Project structure

```
agent-indicator/
  agent-state.sh              # main dispatcher
  backends/
    terminal.sh               # terminal escape sequences
    tmux.sh                   # tmux pane/border/window styling
    sound.sh                  # audio alerts
  hooks/
    claude-hooks.json          # Claude Code hook template
  install.sh                  # installer
```

## License

MIT
