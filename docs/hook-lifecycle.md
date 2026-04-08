# Claude Code Hook Lifecycle

This document explains all 6 Claude Code hook events, what data they receive, what they can output, and how exit codes control behavior.

## Overview

Claude Code hooks are shell scripts that execute at specific points in the Claude Code lifecycle. They allow you to enforce rules, inject context, track state, and automate workflows -- all without modifying Claude Code itself.

```
Session lifecycle:

  SessionStart ──→ [User types prompt] ──→ UserPromptSubmit ──→
  ──→ [Claude picks a tool] ──→ PreToolUse ──→ [Tool executes] ──→ PostToolUse ──→
  ──→ [Claude responds] ──→ Stop
  
  At any point, /compact may trigger:
  ──→ PreCompact ──→ [Context compacted]
```

---

## Event Reference

### 1. SessionStart

**When**: Fires once when a new Claude Code session begins.

**Stdin JSON**:
```json
{
  "session_id": "abc123",
  "cwd": "/path/to/project"
}
```

**Use cases**:
- Load user identity/preferences into context
- Check service status (Docker containers, dev servers)
- Set up session-level tracking files

**Hooks in this gallery**: `load-context.sh`

---

### 2. UserPromptSubmit

**When**: Fires every time the user submits a message, before Claude processes it.

**Stdin JSON**:
```json
{
  "session_id": "abc123",
  "prompt": "the user's message text"
}
```

**Use cases**:
- Scan for accidentally pasted API keys/secrets
- Capture user ratings or feedback signals
- Transform or validate user input

**Hooks in this gallery**: `secret-guard.sh`, `rating-capture.sh`

---

### 3. PreToolUse

**When**: Fires before Claude executes a tool (Bash, Edit, Write, Read, etc.).

**Stdin JSON**:
```json
{
  "session_id": "abc123",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /important"
  }
}
```

**Use cases**:
- Block dangerous commands (`rm`, `git push --force`)
- Enforce workflow rules (dev servers in tmux)
- Track which repos/files are being modified
- Gate PR creation with pre-checks

**Hooks in this gallery**: `bash-guard.sh`, `track-edit.sh`

**Important**: PreToolUse hooks can modify the tool input by writing JSON to stdout. This is how `bash-guard.sh` passes through the original input (or blocks it).

---

### 4. PostToolUse

**When**: Fires after a tool finishes executing.

**Stdin JSON**:
```json
{
  "session_id": "abc123",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file.ts",
    "old_string": "...",
    "new_string": "..."
  },
  "tool_result": "success"
}
```

**Use cases**:
- Run syntax/type checks after code edits
- Detect API signature changes and remind to grep callers
- Track behavior patterns (drift detection)
- Enforce style/quality rules

**Hooks in this gallery**: `ts-check.sh`, `edit-guard.sh`, `nag-reminder.sh`

---

### 5. Stop

**When**: Fires when Claude is about to end its turn (stop generating).

**Stdin JSON**:
```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/session.jsonl",
  "stop_reason": "end_turn"
}
```

**Use cases**:
- Block stopping if repos have uncommitted changes
- Generate session summaries for indexing
- Trigger commit/push workflows
- Save session learnings

**Hooks in this gallery**: `auto-commit.sh`, `session-summary.sh`

**Important**: Stop hooks can block Claude from stopping by outputting:
```json
{"decision": "block", "reason": "explanation for Claude"}
```

---

### 6. PreCompact

**When**: Fires before context is compacted (when conversation gets too long).

**Stdin JSON**:
```json
{
  "session_id": "abc123"
}
```

**Use cases**:
- Save critical state to temp files before context is lost
- Record active checklists, modified repos, open tasks
- Create recovery breadcrumbs

**Hooks in this gallery**: `pre-compact.sh`

---

## Exit Codes

| Exit Code | Meaning | Behavior |
|-----------|---------|----------|
| `0` | Pass | Hook succeeded, continue normally |
| `2` | Block | **PreToolUse/UserPromptSubmit**: Prevents the action and shows stderr to Claude as the reason. **Stop**: Prevents Claude from stopping. |
| Other | Error | Hook failed; Claude Code logs the error and continues |

### Exit Code Examples

**Block a dangerous command** (PreToolUse):
```bash
echo "[GUARD] rm is not allowed! Use mv ~/.Trash/ instead" >&2
exit 2  # Claude sees the stderr message and won't execute the command
```

**Block session end** (Stop):
```bash
cat << EOF
{"decision": "block", "reason": "3 repos have uncommitted changes"}
EOF
# Claude will attempt to commit before trying to stop again
```

**Inject a reminder** (PostToolUse):
```bash
echo '{"message":"<reminder>Write observation notes</reminder>"}'
exit 0  # The message is injected into Claude's context
```

---

## I/O Channels

| Channel | Purpose | When to use |
|---------|---------|-------------|
| **stdin** | Receives event JSON | Always read it (even if you don't need it) |
| **stdout** | Inject content into Claude's context | Messages, reminders, modified tool input |
| **stderr** | Shown to the user / logged | Warnings, status messages, block reasons |

### Important Notes

1. **Always consume stdin**: Even if your hook doesn't need the input data, read it. Some hooks (like `bash-guard.sh`) need to pass stdin through to stdout for the tool to execute.

2. **PreToolUse stdout = tool input**: For PreToolUse hooks, whatever you write to stdout becomes the tool's input. If you want the original command to run unchanged, pipe stdin to stdout: `printf '%s' "$INPUT"`.

3. **stderr for humans, stdout for Claude**: Messages on stderr appear in the UI status area. Messages on stdout get injected into Claude's conversation context.

4. **Keep hooks fast**: Hooks run synchronously. A slow hook blocks Claude's entire response. Target < 500ms per hook.

---

## Hook Profile System

All hooks in this gallery support the Hook Profile system for granular control:

### Disable All Hooks
```bash
export CC_HOOK_PROFILE=off
```

### Disable Specific Hooks
```bash
export CC_DISABLED_HOOKS="nag-reminder.sh,ts-check.sh"
```

### How It Works

Every hook starts with this pattern:
```bash
# === Hook Profile control (inspired by ECC) ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac
```

This checks two things:
1. If `CC_HOOK_PROFILE` is `"off"`, skip the hook entirely
2. If this hook's filename is in the `CC_DISABLED_HOOKS` comma-separated list, skip it

This gives you instant, per-hook control without editing settings.json.

---

## Debugging Hooks

### Test a hook manually
```bash
echo '{"session_id":"test","tool_input":{"command":"rm -rf /"}}' | bash ~/.claude/hooks/safety/bash-guard.sh
```

### Check hook output channels
```bash
# See both stdout and stderr
echo '{}' | bash ~/.claude/hooks/lifecycle/load-context.sh 2>/tmp/hook-stderr.txt
cat /tmp/hook-stderr.txt
```

### Watch hook execution in real-time
```bash
# Tail the session tracking files while Claude works
watch -n1 'cat /tmp/cc-session-repos-* 2>/dev/null; echo "---"; cat /tmp/cc-nag-tracker-* 2>/dev/null'
```
