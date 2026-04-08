#!/bin/bash
# rating-capture.sh - UserPromptSubmit Hook
# Captures explicit user ratings (1-10) and records them to a JSONL file
#
# Trigger: UserPromptSubmit
# Input: stdin JSON (prompt, session_id)
# Output: no stdout (doesn't inject into context)
# Side effect: appends to ratings.jsonl

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

# === CUSTOMIZE THIS ===
RATINGS_FILE="${CC_RATINGS_FILE:-$HOME/.claude/ratings.jsonl}"

# Read stdin
INPUT=$(cat)

# Extract prompt and session_id
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")

# Check if the message is a rating (1-10 at start, optional separator + comment)
# Excludes "7 items", "3 files", etc. (false positives)
RATING=$(echo "$PROMPT" | python3 -c "
import sys, re
prompt = sys.stdin.read().strip()
# Match: starts with 1-10, optionally followed by separator + comment
match = re.match(r'^(10|[1-9])(?:\s*[-:]\s*|\s+)?(.*)$', prompt)
if not match:
    sys.exit(1)
rating = int(match.group(1))
comment = match.group(2).strip() if match.group(2) else ''
# Exclude cases where a unit word follows (not a rating)
if comment:
    non_rating = re.match(r'^(items?|things?|steps?|files?|lines?|bugs?|issues?|errors?|times?|minutes?|hours?|days?|seconds?|percent|%|th\b|st\b|nd\b|rd\b|of\b|in\b|at\b|to\b|the\b|a\b|an\b)', comment, re.I)
    if non_rating:
        sys.exit(1)
print(f'{rating}|{comment}')
" 2>/dev/null)

# If not a rating, exit silently
if [ $? -ne 0 ] || [ -z "$RATING" ]; then
  exit 0
fi

# Parse rating and comment
SCORE=$(echo "$RATING" | cut -d'|' -f1)
COMMENT=$(echo "$RATING" | cut -d'|' -f2-)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Ensure directory exists
mkdir -p "$(dirname "$RATINGS_FILE")"

# Write to ratings.jsonl
if [ -n "$COMMENT" ]; then
  echo "{\"timestamp\":\"$TIMESTAMP\",\"rating\":$SCORE,\"comment\":\"$COMMENT\",\"session_id\":\"$SESSION_ID\"}" >> "$RATINGS_FILE"
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"rating\":$SCORE,\"session_id\":\"$SESSION_ID\"}" >> "$RATINGS_FILE"
fi

echo "[rating-capture] Recorded rating: $SCORE" >&2

exit 0
