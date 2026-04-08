#!/bin/bash
# ts-check.sh -- PostToolUse: Quick syntax check after Edit/Write
# Walks up from the edited file to find package.json (project root),
# then runs the fastest available check
# 2026-03-17 created

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

FILE="$CLAUDE_TOOL_INPUT_FILE_PATH"
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0

# Walk up to find project root (directory with package.json)
DIR=$(dirname "$FILE")
ROOT=""
while [[ "$DIR" != "/" && "$DIR" != "$HOME" ]]; do
  [[ -f "$DIR/package.json" ]] && { ROOT="$DIR"; break; }
  DIR=$(dirname "$DIR")
done
[[ -z "$ROOT" ]] && exit 0

# Prefer project's own check script, otherwise use available tools
cd "$ROOT"

# Customize: change 'bun' to 'npx'/'pnpm' based on your package manager
RUNNER="${CC_PACKAGE_RUNNER:-npx}"

if grep -q '"check"' package.json 2>/dev/null; then
  $RUNNER run check 2>&1 | head -20
elif grep -q '"typecheck"' package.json 2>/dev/null; then
  $RUNNER run typecheck 2>&1 | head -20
elif [[ -f "tsconfig.json" ]]; then
  npx tsc --noEmit 2>&1 | head -20
else
  # Lightest check: single-file syntax via node --check (JS only)
  if [[ "$FILE" == *.js || "$FILE" == *.mjs ]]; then
    node --check "$FILE" 2>&1 | head -10
  fi
fi
