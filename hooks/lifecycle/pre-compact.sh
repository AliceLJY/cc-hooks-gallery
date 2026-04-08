#!/bin/bash
# pre-compact.sh - PreCompact Hook
# Saves critical context to a temp file before compact, preventing context loss
# Inspired by ECC pre-compact mechanism
# 2026-03-28 created

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','unknown'))" 2>/dev/null || echo "unknown")

SAVE_DIR="/tmp/cc-pre-compact"
mkdir -p "$SAVE_DIR"
SAVE_FILE="$SAVE_DIR/${SESSION_ID}.md"

# Collect active checklists/plans from Desktop (customize the pattern)
CHECKLISTS=""
CHECKLIST_PATTERN="${CC_CHECKLIST_PATTERN:-$HOME/Desktop/*checklist*.md}"
for f in $CHECKLIST_PATTERN; do
  [ -f "$f" ] && CHECKLISTS="${CHECKLISTS}\n- $(basename "$f")"
done

# Collect repos touched during this session
TRACK_FILE="/tmp/cc-session-repos-${SESSION_ID}"
REPOS=""
if [ -f "$TRACK_FILE" ]; then
  REPOS=$(cat "$TRACK_FILE" | sed 's/^/- /')
fi

TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

cat > "$SAVE_FILE" << EOF
# Pre-Compact State: $TIMESTAMP
Session: $SESSION_ID

## Active Checklists
${CHECKLISTS:-"(none)"}

## Repos Touched This Session
${REPOS:-"(none)"}

## Recovery Hint
If you lost context after compact, read this file: $SAVE_FILE
EOF

echo "[pre-compact] Saved pre-compact state to $SAVE_FILE" >&2
exit 0
