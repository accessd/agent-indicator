# AGENTS.md

## Cursor Cloud specific instructions

This is a shell + Python (stdlib-only) project with no build step, no package manager, and no automated test suite. See `CLAUDE.md` for architecture details and manual testing commands.

### Running the application

The entry point is `./agent-state.sh`. In headless/CI environments (no real TTY), always pass `--tty /dev/pts/0` (or another valid pts) to avoid "not a tty" fallback issues:

```bash
./agent-state.sh --state running --tty /dev/pts/0
./agent-state.sh --state needs-input --tty /dev/pts/0
./agent-state.sh --state done --tty /dev/pts/0
./agent-state.sh --state off --tty /dev/pts/0
```

Set `AGENT_INDICATOR_LOG_LEVEL=debug` for verbose stderr output when troubleshooting.

### Linting

```bash
shellcheck -x agent-state.sh backends/*.sh lib/*.sh adapters/*.sh setup.sh install.sh
```

Shellcheck reports SC1003 (info) on `backends/terminal.sh` for intentional escape sequences — these are false positives. SC2001 (style) in `setup.sh` is a known minor suggestion.

### Config system

`python3 config/config.py` manages `~/.config/agent-indicator/config.json`. Run `--ensure` to initialize the config file with defaults, `--dump` to inspect merged config, `--shell-exports` to see the env vars the dispatcher will eval.

### Gotchas

- `setup.sh` is an interactive TUI wizard — do not run it in non-interactive (headless) sessions. Use `config/config.py --set` for programmatic config changes instead.
- The `needs-input` and `done` states take ~3 seconds due to the terminal background color restore timeout (`bg_restore_timeout` defaults to 3). This is expected behavior, not a hang.
- Sound, desktop, and push backends are disabled by default. Only the terminal backend runs out of the box.
