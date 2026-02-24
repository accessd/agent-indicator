#!/usr/bin/env bash
# Sound backend: plays audio alerts from CESP packs or system sounds.
# Supports no-repeat selection, volume control, and player fallback chain.

set -euo pipefail

SOUND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOUND_PACKS_DIR="${SOUND_SCRIPT_DIR}/../packs"
SOUND_STATE_DIR="${TMPDIR:-/tmp}"

# ---------------------------------------------------------------------------
# System sound paths
# ---------------------------------------------------------------------------
_system_sound_path() {
    local name="$1"
    # macOS
    local macos_path="/System/Library/Sounds/${name}.aiff"
    if [ -f "$macos_path" ]; then
        printf '%s' "$macos_path"
        return
    fi
    # Linux freedesktop
    local fd_dirs=(
        "/usr/share/sounds/freedesktop/stereo"
        "/usr/share/sounds/gnome/default/alerts"
        "/usr/share/sounds/ubuntu/stereo"
    )
    local lower
    lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    for dir in "${fd_dirs[@]}"; do
        for ext in wav ogg oga; do
            if [ -f "${dir}/${lower}.${ext}" ]; then
                printf '%s' "${dir}/${lower}.${ext}"
                return
            fi
        done
    done
}

# ---------------------------------------------------------------------------
# CESP pack loader
# ---------------------------------------------------------------------------
_load_pack_sounds() {
    local pack="$1"
    local state="$2"
    local pack_dir="${SOUND_PACKS_DIR}/${pack}"
    local manifest="${pack_dir}/openpeon.json"

    if [ ! -f "$manifest" ]; then
        return
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        return
    fi

    # Python extracts sound entries for the given state, resolves paths
    python3 - "$manifest" "$state" "$pack_dir" <<'PY'
import json, sys, os

manifest_path, state, pack_dir = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    manifest = json.loads(open(manifest_path).read())
except Exception:
    sys.exit(0)

sounds = manifest.get("sounds", {}).get(state, [])
for entry in sounds:
    if "file" in entry:
        path = os.path.join(pack_dir, entry["file"])
        if os.path.isfile(path):
            print(path)
    elif "system" in entry:
        # Output system:<name> for shell to resolve
        print(f"system:{entry['system']}")
PY
}

# ---------------------------------------------------------------------------
# No-repeat picker: avoid playing the same sound twice in a row
# ---------------------------------------------------------------------------
_pick_sound() {
    local state="$1"
    shift
    local sounds=("$@")

    if [ ${#sounds[@]} -eq 0 ]; then
        return
    fi

    if [ ${#sounds[@]} -eq 1 ]; then
        printf '%s' "${sounds[0]}"
        return
    fi

    local last_file="${SOUND_STATE_DIR}/agent-indicator-last-sound-${state}"
    local last=""
    if [ -f "$last_file" ]; then
        last=$(head -1 "$last_file" 2>/dev/null || true)
    fi

    # Filter out last played, pick random from remainder
    local candidates=()
    for s in "${sounds[@]}"; do
        if [ "$s" != "$last" ]; then
            candidates+=("$s")
        fi
    done

    if [ ${#candidates[@]} -eq 0 ]; then
        candidates=("${sounds[@]}")
    fi

    local idx=$(( RANDOM % ${#candidates[@]} ))
    local picked="${candidates[$idx]}"

    printf '%s' "$picked" > "$last_file"
    printf '%s' "$picked"
}

# ---------------------------------------------------------------------------
# Player chain
# ---------------------------------------------------------------------------
_play_file() {
    local file="$1"
    local volume="${2:-}"

    if [ ! -f "$file" ]; then
        return
    fi

    if command -v afplay >/dev/null 2>&1; then
        # macOS: afplay is the only player, no fallback needed
        if [ -n "$volume" ]; then
            afplay -v "$volume" "$file" &
        else
            afplay "$file" &
        fi
    else
        # Linux/other: try players in order, fall through on failure.
        # Runs in a subshell so that if e.g. paplay fails (PulseAudio not
        # running), we automatically try aplay, then play (SoX).
        local pavol=""
        if [ -n "$volume" ] && command -v bc >/dev/null 2>&1; then
            pavol=$(printf '%.0f' "$(echo "$volume * 65536" | bc)")
        fi
        (
            if command -v paplay >/dev/null 2>&1; then
                if [ -n "$pavol" ]; then
                    paplay --volume="$pavol" "$file" && exit 0
                else
                    paplay "$file" && exit 0
                fi
            fi
            if command -v aplay >/dev/null 2>&1; then
                aplay -q "$file" && exit 0
            fi
            if command -v play >/dev/null 2>&1; then
                if [ -n "$volume" ]; then
                    play -q -v "$volume" "$file" && exit 0
                else
                    play -q "$file" && exit 0
                fi
            fi
        ) 2>/dev/null &
    fi
    disown 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Public entry point
# Called by agent-state.sh: source backends/sound.sh; sound_apply <state>
#
# Env vars (set by config system or user):
#   AGENT_INDICATOR_SOUND_PACK               - pack name (default: "default")
#   AGENT_INDICATOR_SOUND_VOLUME             - 0.0-1.0
#   AGENT_INDICATOR_SOUND_STATE_NEEDS_INPUT  - on/off
#   AGENT_INDICATOR_SOUND_STATE_DONE         - on/off
#   AGENT_INDICATOR_SOUND_COMMAND            - override: custom command
#   AGENT_INDICATOR_SOUND_NEEDS_INPUT        - override: specific file
#   AGENT_INDICATOR_SOUND_DONE               - override: specific file
# ---------------------------------------------------------------------------
sound_apply() {
    local state="$1"

    # Custom command overrides everything
    if [ -n "${AGENT_INDICATOR_SOUND_COMMAND:-}" ]; then
        case "$state" in
            needs-input|done)
                eval "$AGENT_INDICATOR_SOUND_COMMAND" "$state" &
                disown 2>/dev/null || true
                ;;
        esac
        return
    fi

    # Per-state file overrides
    case "$state" in
        needs-input)
            if [ "${AGENT_INDICATOR_SOUND_STATE_NEEDS_INPUT:-on}" = "off" ]; then
                return
            fi
            if [ -n "${AGENT_INDICATOR_SOUND_NEEDS_INPUT:-}" ]; then
                _play_file "${AGENT_INDICATOR_SOUND_NEEDS_INPUT}" "${AGENT_INDICATOR_SOUND_VOLUME:-}"
                return
            fi
            ;;
        done)
            if [ "${AGENT_INDICATOR_SOUND_STATE_DONE:-on}" = "off" ]; then
                return
            fi
            if [ -n "${AGENT_INDICATOR_SOUND_DONE:-}" ]; then
                _play_file "${AGENT_INDICATOR_SOUND_DONE}" "${AGENT_INDICATOR_SOUND_VOLUME:-}"
                return
            fi
            ;;
        *)
            return
            ;;
    esac

    # Load from CESP pack
    local pack="${AGENT_INDICATOR_SOUND_PACK:-default}"
    local raw_sounds
    raw_sounds=$(_load_pack_sounds "$pack" "$state" 2>/dev/null || true)

    local resolved=()
    if [ -n "$raw_sounds" ]; then
        while IFS= read -r line; do
            if [[ "$line" == system:* ]]; then
                local sys_name="${line#system:}"
                local sys_path
                sys_path=$(_system_sound_path "$sys_name")
                if [ -n "$sys_path" ]; then
                    resolved+=("$sys_path")
                fi
            elif [ -f "$line" ]; then
                resolved+=("$line")
            fi
        done <<< "$raw_sounds"
    fi

    # Fallback to hardcoded system sounds if pack yielded nothing
    if [ ${#resolved[@]} -eq 0 ]; then
        local fallback=""
        case "$state" in
            needs-input) fallback=$(_system_sound_path "Funk") ;;
            done)        fallback=$(_system_sound_path "Glass") ;;
        esac
        if [ -n "$fallback" ]; then
            resolved+=("$fallback")
        fi
    fi

    if [ ${#resolved[@]} -eq 0 ]; then
        return
    fi

    local picked
    picked=$(_pick_sound "$state" "${resolved[@]}")
    if [ -n "$picked" ]; then
        _play_file "$picked" "${AGENT_INDICATOR_SOUND_VOLUME:-}"
    fi
}
