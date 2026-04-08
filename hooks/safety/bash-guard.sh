#!/bin/bash
# bash-guard.sh -- Bash PreToolUse unified gatekeeper
# Merges all Bash PreToolUse checks into a single entry point
# Check order: hard-block (rm / dev-server) -> soft-warn (tmux / git push) -> repo tracking
# 2026-02-28 created

# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

INPUT=$(cat)

# No input -> pass through
[[ -z "$INPUT" ]] && exit 0

# ========== Extract command ==========
CMD=$(node -e "
let d='';
process.stdin.on('data',c=>d+=c);
process.stdin.on('end',()=>{
    try { console.log(JSON.parse(d).tool_input?.command || ''); }
    catch { console.log(''); }
});" <<< "$INPUT")

# No command extracted -> pass through
[[ -z "$CMD" ]] && { printf '%s' "$INPUT"; exit 0; }

# ========== Subagent detection ==========
# bypassPermissions can't bypass hooks; subagents need separate handling
# Process tree: main session = bash -> claude -> zsh
#               subagent     = bash -> claude(sub) -> claude(main) -> zsh
# Detection: grandparent process is claude -> subagent
IS_SUBAGENT=""
[[ -n "${CLAUDE_SUBAGENT:-}" ]] && IS_SUBAGENT=1
if [[ -z "$IS_SUBAGENT" ]]; then
    GP_PID=$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ' || true)
    GP_COMM=$(ps -o comm= -p "$GP_PID" 2>/dev/null || true)
    [[ "$GP_COMM" == "claude" ]] && IS_SUBAGENT=1
fi

# ========== Hard blocks (main session blocks, subagent downgrades to warning) ==========
if [[ -z "$IS_SUBAGENT" ]]; then
    # CHECK 1: rm hard-block -- force use Trash
    # Enforces the "NEVER rm" rule at the harness level (defense in depth)
    if echo "$CMD" | grep -qE '\brm\s+(-[a-zA-Z]*\s+)*[/~.]'; then
        cat >&2 <<EOF
[RM-GUARD] Blocked: rm is not allowed!
  Use instead: mv <file> ~/.Trash/
EOF
        exit 2
    fi

    # CHECK 2: Dev server must run in tmux (hard-block exit 2)
    if [[ "$(uname)" != MINGW* ]] && echo "$CMD" | grep -qE '(npm run dev\b|pnpm( run)? dev\b|yarn dev\b|bun run dev\b)'; then
        cat >&2 <<EOF
[TMUX-DEV] Blocked: Dev servers must run inside tmux!
  Use: tmux new-session -d -s dev "npm run dev"
  Then: tmux attach -t dev
EOF
        exit 2
    fi
else
    # Subagent: rm downgraded to warning, not blocked
    if echo "$CMD" | grep -qE '\brm\s+(-[a-zA-Z]*\s+)*[/~.]'; then
        echo "[RM-GUARD] Warning: subagent rm detected -- consider using mv ~/.Trash/ instead" >&2
    fi
fi

# ========== CHECK 3: Long-running command tmux reminder (soft warn, no block) ==========
if [[ "$(uname)" != MINGW* ]] && [[ -z "$TMUX" ]]; then
    if echo "$CMD" | grep -qE '(npm (install|test)|pnpm (install|test)|yarn (install|test)?|bun (install|test)|cargo build|make\b|docker\b|pytest|vitest|playwright)'; then
        cat >&2 <<EOF
[TMUX-HINT] Consider running in tmux to preserve session
  tmux new -s dev  |  tmux attach -t dev
EOF
    fi
fi

# ========== CHECK 4: git push reminder (soft warn, no block) ==========
if echo "$CMD" | grep -qE 'git push'; then
    echo "[GIT-PUSH] Pushing to remote... confirm changes are reviewed" >&2
fi

# ========== TRACK: Record which repos this session has touched ==========
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || echo "")
if [[ -n "$SESSION_ID" ]]; then
    source ~/.claude/hooks/repos.conf 2>/dev/null
    TRACK_FILE="/tmp/cc-session-repos-${SESSION_ID}"
    for REPO in "${TRACKED_REPOS[@]}"; do
        # Expand ~ and $HOME
        REPO_EXPANDED="${REPO/#\~/$HOME}"
        REPO_BASE=$(basename "$REPO_EXPANDED")
        # Command references repo path or repo name + git operation -> track it
        if echo "$CMD" | grep -qF "$REPO_EXPANDED" || echo "$CMD" | grep -qF "$REPO_BASE"; then
            grep -qxF "$REPO_EXPANDED" "$TRACK_FILE" 2>/dev/null || echo "$REPO_EXPANDED" >> "$TRACK_FILE"
        fi
    done
fi

# ========== CHECK 5: gh pr create gatekeeper ==========
# Promote paper rules into code:
# Rule 1: Check for existing PRs before creating new ones (prevent duplicates)
# Rule 2: Own repos -> merge directly, don't PR yourself
if echo "$CMD" | grep -qE '\bgh\s+pr\s+create\b'; then
    # Extract --repo argument (if present)
    PR_REPO=$(echo "$CMD" | grep -oE '\-\-repo[= ]\s*[^ ]+' | sed 's/--repo[= ]*//')
    if [[ -n "$PR_REPO" ]]; then
        PR_OWNER=$(echo "$PR_REPO" | cut -d'/' -f1)
    fi

    # Check if this is your own repo (customize CC_GITHUB_OWNERS)
    CC_GITHUB_OWNERS="${CC_GITHUB_OWNERS:-}"
    if [[ -n "$CC_GITHUB_OWNERS" && -n "$PR_OWNER" ]]; then
        for OWNER in $(echo "$CC_GITHUB_OWNERS" | tr ',' ' '); do
            if [[ "$PR_OWNER" == "$OWNER" ]]; then
                cat >&2 <<EOF
[PR-GUARD] Target repo belongs to $PR_OWNER -- consider merging directly instead of PR.
  Fix: git checkout main && git merge <branch> && git push
  Ignore this if you need PR for CI validation.
EOF
                break
            fi
        done
    fi

    # Remind to check existing PRs
    cat >&2 <<'EOF'
[PR-GUARD] Before creating PR, confirm:
  1. No existing open PR fixing the same issue? (run: gh pr list --state open)
  2. Target branch correct?
EOF
fi

# ========== All checks passed, pass through ==========
printf '%s' "$INPUT"
exit 0
