#!/bin/bash
# load-context.sh - SessionStart Hook
# Automatically loads identity profile and active project state at session start
#
# Trigger: SessionStart
# Output: stdout -> injected into Claude Code context
# Dependencies: identity config (customize below)

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

# === CUSTOMIZE THESE ===
# Memory directory: where your project memory files live
MEMORY_DIR="${CC_MEMORY_DIR:-$HOME/.claude/memory}"
IDENTITY_FILE="$MEMORY_DIR/identity.md"

# One-line identity summary (customize this to your own profile)
# This gets injected into every new session as baseline context.
# For a full identity file, create $MEMORY_DIR/identity.md
IDENTITY_SUMMARY="${CC_IDENTITY_SUMMARY:-"Edit this line in load-context.sh or set CC_IDENTITY_SUMMARY env var. Example: Senior dev, GitHub: username, prefers commit+push after changes, uses Trash instead of rm."}"

# Check Docker container status (quick check, 2s timeout)
BOT_STATUS=""
if command -v docker &> /dev/null; then
  # Customize the filter to match your container names
  BOT_STATUS=$(timeout 2 docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null | head -5)
fi

# Output to stdout -- Claude Code injects this into context
cat << EOF

--- Auto-loaded context (load-context.sh) ---

# User Identity (see $IDENTITY_FILE for full profile)
$IDENTITY_SUMMARY

## Active Services
${BOT_STATUS:-"(Docker not running or check timed out)"}

--- Context loaded ---

EOF
