All done. Here's what was built:

## Deliverable Summary

**16 files** (8 new, 4 rewritten, 4 unchanged)

### New files
| File | Purpose |
|---|---|
| `lib/log.sh` | Stderr logger with verbosity levels (quiet/error/warn/info/debug) |
| `lib/platform.sh` | Detects OS (macOS/Linux/WSL) and 11 tools at source time |
| `config/defaults.json` | Default config for all 5 backends |
| `config/config.py` | Config read/write/merge. `--shell-exports` bridges JSON config to env vars |
| `backends/desktop.sh` | macOS: osascript + terminal-notifier. Linux: notify-send. Templated title/body |
| `backends/push.sh` | curl POST to ntfy, Pushover, or Telegram. All backgrounded |
| `packs/default/openpeon.json` | CESP v1.0 manifest referencing system sounds (Funk, Ping, Tink, Glass, Hero, Purr) |
| `setup.sh` | Interactive TUI wizard: 7 steps from platform detection through test |

### Rewritten files
| File | Changes |
|---|---|
| `agent-state.sh` | Loads config via `config.py --shell-exports`, sources lib/, dispatches to 5 backends. Backwards compatible with env vars |
| `backends/sound.sh` | CESP pack loader, no-repeat picker (tracks last played per state), volume control on afplay/paplay/play. Falls back to system sounds |
| `install.sh` | Copies new dirs (lib/, config/, packs/). Added `--uninstall`, `--headless`, `--setup` flags |
| `CLAUDE.md` | Documents new architecture, all 5 backends, config system |

### Unchanged
`backends/terminal.sh`, `backends/tmux.sh`, `hooks/claude-hooks.json`, `README.md`

### Design decisions made
- **No vendoring.** Terminal and tmux backends stay inline. They're complete implementations with no reason to delegate to external repos.
- **Config as env var bridge.** `config.py --shell-exports` runs once at dispatcher startup, outputs env var exports. Backends only read env vars. Python is only called once per invocation, not per-backend.
- **Env vars always win.** `config.py` skips exports for vars already in the environment. Users who set `AGENT_INDICATOR_SOUND=on` in their shell profile get that honored over config.json.
- **System sounds in default pack.** The CESP manifest references system sounds by name instead of shipping binary audio files. The sound backend resolves names to platform-specific paths.
- **Graceful degradation throughout.** Missing python3 = config skipped, env vars still work. Missing tools per backend = that backend warns and skips. Other backends still fire.
