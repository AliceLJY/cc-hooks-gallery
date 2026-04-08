#!/bin/bash
# secret-guard.sh - UserPromptSubmit Hook
# Detects API keys / secrets in user messages and blocks submission
# Inspired by ECC before-submit-prompt mechanism
# 2026-03-28 created

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

INPUT=$(cat)

# Extract user message
MSG=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null || echo "")

[ -z "$MSG" ] && exit 0

# 5 secret pattern categories:
# 1. OpenAI/Anthropic API keys (sk-...)
# 2. Claude Partner keys (sk-cp-...)
# 3. GitHub Personal Access Tokens (ghp_...)
# 4. AWS Access Keys (AKIA...)
# 5. Slack tokens (xox[bpsa]-...)
# 6. PEM private keys (-----BEGIN...PRIVATE KEY-----)
if echo "$MSG" | grep -qE '(sk-[a-zA-Z0-9]{20,}|sk-cp-[a-zA-Z0-9_-]{20,}|ghp_[a-zA-Z0-9]{36,}|AKIA[A-Z0-9]{16}|xox[bpsa]-[a-zA-Z0-9-]+|-----BEGIN[[:space:]]+(RSA[[:space:]]+|EC[[:space:]])?PRIVATE KEY-----)'; then
  echo "[SECRET-GUARD] Potential API key / secret detected! Please confirm before sending." >&2
  exit 2  # block
fi

exit 0
