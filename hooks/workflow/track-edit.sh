#!/bin/bash
# track-edit.sh -- Edit/Write repo tracking
# Records which tracked repos this session has modified via Edit/Write tools
# Works with auto-commit.sh for per-session commit reminders
# 2026-03-04 created

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

INPUT=$(cat)
[[ -z "$INPUT" ]] && exit 0

# Extract file_path and session_id
eval "$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
fp = d.get('tool_input', {}).get('file_path', '')
sid = d.get('session_id', '')
print(f'FILE_PATH=\"{fp}\"')
print(f'SESSION_ID=\"{sid}\"')
" 2>/dev/null)"

[[ -z "$SESSION_ID" || -z "$FILE_PATH" ]] && { printf '%s' "$INPUT"; exit 0; }

# Load repo list from config
source ~/.claude/hooks/repos.conf 2>/dev/null

TRACK_FILE="/tmp/cc-session-repos-${SESSION_ID}"
for REPO in "${TRACKED_REPOS[@]}"; do
    REPO_EXPANDED="${REPO/#\~/$HOME}"
    # file_path is under this repo directory -> record it
    if [[ "$FILE_PATH" == "$REPO_EXPANDED"/* ]]; then
        grep -qxF "$REPO_EXPANDED" "$TRACK_FILE" 2>/dev/null || echo "$REPO_EXPANDED" >> "$TRACK_FILE"
        break
    fi
done

# Pass through
printf '%s' "$INPUT"
exit 0
