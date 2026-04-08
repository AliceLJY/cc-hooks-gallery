#!/bin/bash
# auto-commit.sh - Stop Hook
# When a task ends, scan repos touched during this session for uncommitted changes
# and block Claude from stopping until changes are committed.
#
# Trigger: Stop (runs after session-summary.sh)
# Anti-loop: Max 2 blocks per session, then pass through
# Per-session tracking: no cross-window interference

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

# Read stdin
INPUT=$(cat)

# Extract session_id
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','unknown'))" 2>/dev/null || echo "unknown")

# ===== Read this session's repo tracking file =====
TRACK_FILE="/tmp/cc-session-repos-${SESSION_ID}"

if [ ! -f "$TRACK_FILE" ]; then
  # This session didn't touch any tracked repos, pass through
  exit 0
fi

# Read repo list from tracking file
mapfile -t REPOS < "$TRACK_FILE"

if [ ${#REPOS[@]} -eq 0 ]; then
  exit 0
fi

# ===== Anti-loop protection =====
LOCK_FILE="/tmp/cc-autocommit-${SESSION_ID}"

if [ -f "$LOCK_FILE" ]; then
  COUNT=$(cat "$LOCK_FILE" 2>/dev/null || echo "0")
  if [ "$COUNT" -ge 2 ]; then
    # Already blocked 2 times, pass through (prevent infinite loop)
    rm -f "$LOCK_FILE"
    rm -f "$TRACK_FILE"
    exit 0
  fi
  echo $((COUNT + 1)) > "$LOCK_FILE"
else
  echo "1" > "$LOCK_FILE"
fi

# ===== Scan repos touched during this session =====
DIRTY_REPOS=()

for REPO in "${REPOS[@]}"; do
  [ -d "$REPO/.git" ] || continue

  # Check: modified / staged / untracked (ignore submodule dirty state)
  if ! git -C "$REPO" diff --quiet --ignore-submodules=dirty 2>/dev/null \
     || ! git -C "$REPO" diff --cached --quiet --ignore-submodules=dirty 2>/dev/null \
     || [ -n "$(git -C "$REPO" ls-files --others --exclude-standard 2>/dev/null)" ]; then
    REPO_NAME=$(basename "$REPO")
    DIRTY_REPOS+=("$REPO_NAME ($REPO)")
  fi
done

# ===== Check for unpushed commits ==========
UNPUSHED_REPOS=()

for REPO in "${REPOS[@]}"; do
  [ -d "$REPO/.git" ] || continue

  # Has upstream and unpushed commits
  AHEAD=$(git -C "$REPO" log --oneline '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$AHEAD" -gt 0 ]; then
    REPO_NAME=$(basename "$REPO")
    UNPUSHED_REPOS+=("$REPO_NAME: ${AHEAD} commits unpushed ($REPO)")
  fi
done

# No dirty repos and no unpushed commits -> cleanup and pass
if [ ${#DIRTY_REPOS[@]} -eq 0 ] && [ ${#UNPUSHED_REPOS[@]} -eq 0 ]; then
  rm -f "$LOCK_FILE"
  rm -f "$TRACK_FILE"
  exit 0
fi

# ===== Build block message =====
REASON=""

if [ ${#DIRTY_REPOS[@]} -gt 0 ]; then
  REPO_LIST=""
  for R in "${DIRTY_REPOS[@]}"; do
    REPO_LIST="${REPO_LIST}\n- ${R}"
  done
  REASON="Found ${#DIRTY_REPOS[@]} repo(s) with uncommitted changes:${REPO_LIST}\n\nPlease commit before ending the session."
fi

if [ ${#UNPUSHED_REPOS[@]} -gt 0 ]; then
  PUSH_LIST=""
  for R in "${UNPUSHED_REPOS[@]}"; do
    PUSH_LIST="${PUSH_LIST}\n- ${R}"
  done
  if [ -n "$REASON" ]; then
    REASON="${REASON}\n\n"
  fi
  REASON="${REASON}Found ${#UNPUSHED_REPOS[@]} repo(s) with unpushed commits:${PUSH_LIST}\n\nPlease confirm whether to git push."
fi

cat << EOF
{"decision": "block", "reason": "${REASON}"}
EOF
