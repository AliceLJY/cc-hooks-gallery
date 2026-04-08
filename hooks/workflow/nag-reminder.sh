#!/bin/bash
# nag-reminder.sh -- PostToolUse: behavior drift detection + gentle reminder
# Source: learn-claude-code s03 "nag reminder" concept
# Principle: Track tool call counts; if the model calls tools N times without
#            performing expected behavior, inject a reminder
#
# Current detection rule:
#   - ReAct observation: 5+ consecutive tool calls without writing observation notes
#     (The workflow requires: "after each step, read results and assess if expected")
#
# Tracking file: /tmp/cc-nag-tracker-${SESSION_ID}.json
# Trigger: PostToolUse (all tools)
# Output: stdout -> message injected as reminder
# 2026-03-28 created

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

# === Read stdin ===
INPUT=$(cat)
[[ -z "$INPUT" ]] && exit 0

# === Extract fields (pure bash + jq, no node/python dependency) ===
# PostToolUse hook receives JSON with: tool_name, tool_input, session_id, etc.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# No session_id or tool_name -> skip
[[ -z "$SESSION_ID" || -z "$TOOL_NAME" ]] && exit 0

# === Tracking file path ===
TRACKER="/tmp/cc-nag-tracker-${SESSION_ID}.json"

# === Initialize tracking file ===
if [[ ! -f "$TRACKER" ]]; then
    echo '{"call_count":0,"last_observe_at":0}' > "$TRACKER"
fi

# === Read current state ===
CALL_COUNT=$(jq -r '.call_count // 0' "$TRACKER" 2>/dev/null || echo 0)
LAST_OBSERVE=$(jq -r '.last_observe_at // 0' "$TRACKER" 2>/dev/null || echo 0)

# === Increment counter ===
CALL_COUNT=$((CALL_COUNT + 1))

# === Detect "writing observation notes" behavior ===
# Criteria: Edit/Write tool + content contains observation markers
# This indicates the model is executing the ReAct step-level feedback loop
IS_OBSERVATION=0
if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
    # Check if tool_input contains observation markers
    CONTENT=$(echo "$INPUT" | jq -r '
        (.tool_input.new_string // "") + " " + (.tool_input.content // "")
    ' 2>/dev/null)
    if echo "$CONTENT" | grep -qE '\[Observe[::]|\[observe[::]|Observation[::]'; then
        IS_OBSERVATION=1
    fi
fi

# === Update state ===
if [[ "$IS_OBSERVATION" -eq 1 ]]; then
    # Wrote observation notes -> reset counter
    LAST_OBSERVE=$CALL_COUNT
fi

# Write back tracking file (atomic write to avoid race conditions)
TMP_TRACKER="${TRACKER}.tmp"
jq -n \
    --argjson cc "$CALL_COUNT" \
    --argjson lo "$LAST_OBSERVE" \
    '{"call_count":$cc,"last_observe_at":$lo}' > "$TMP_TRACKER" 2>/dev/null \
    && mv "$TMP_TRACKER" "$TRACKER"

# === Drift detection ===
SINCE_LAST=$((CALL_COUNT - LAST_OBSERVE))
NAG_THRESHOLD=${CC_NAG_THRESHOLD:-5}  # Customizable via environment variable

# Remind every NAG_THRESHOLD calls (avoid per-call noise)
if [[ "$SINCE_LAST" -ge "$NAG_THRESHOLD" ]] && \
   [[ $((SINCE_LAST % NAG_THRESHOLD)) -eq 0 ]]; then
    # Output reminder to stdout (Claude Code injects into model context)
    cat << 'REMINDER'
{"message":"<reminder>You've executed multiple steps without writing observation notes. Per the ReAct workflow:\n1. Read the actual result after each step -- did it match expectations?\n2. If unexpected -> stop and diagnose\n3. Record [Observe: ...] note (one line: what happened, any surprise)\nPlease add observation notes at the next appropriate point.</reminder>"}
REMINDER
fi

exit 0
