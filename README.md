# cc-hooks-gallery

**Production-grade Claude Code hooks from 500+ real sessions**

[![Hooks](https://img.shields.io/badge/hooks-12-blue)](#hook-catalog)
[![Lifecycle Events](https://img.shields.io/badge/lifecycle_events-6-green)](#hook-lifecycle)
[![License](https://img.shields.io/badge/license-MIT-orange)](LICENSE)

Battle-tested Claude Code hooks for safety, workflow automation, and productivity. Every hook in this gallery was forged in real daily usage -- not theoretical examples, but solutions to actual problems encountered across hundreds of Claude Code sessions.

---

## Hook Lifecycle

Claude Code fires hooks at 6 lifecycle events. Here's the full picture:

```
                         cc-hooks-gallery coverage
                         ─────────────────────────

  ┌─────────────┐     ┌───────────────────┐     ┌──────────────┐
  │ SessionStart │────▶│ UserPromptSubmit  │────▶│  PreToolUse  │
  │              │     │                   │     │              │
  │ load-context │     │ secret-guard      │     │ bash-guard   │
  │              │     │ rating-capture    │     │ track-edit   │
  └─────────────┘     └───────────────────┘     └──────┬───────┘
                                                       │
                                                       ▼
  ┌─────────────┐     ┌───────────────────┐     ┌──────────────┐
  │  PreCompact  │◀───│      Stop         │◀────│ PostToolUse  │
  │              │     │                   │     │              │
  │ pre-compact  │     │ session-summary   │     │ ts-check     │
  │              │     │ auto-commit       │     │ edit-guard   │
  └─────────────┘     └───────────────────┘     │ nag-reminder │
                                                └──────────────┘
```

Each hook is a standalone bash script that receives JSON on stdin and communicates via stdout (inject into Claude's context) and stderr (show to user). Exit code `2` = block the action.

---

## Quick Start

```bash
# Clone and install
git clone https://github.com/AliceLJY/cc-hooks-gallery.git
cd cc-hooks-gallery
bash install.sh           # Interactive: choose which hooks to enable
bash install.sh --all     # Install everything
bash install.sh --dry-run # Preview without changes
```

The installer backs up your existing `settings.json`, copies hooks to `~/.claude/hooks/`, and merges the configuration.

---

## Hook Catalog

| Hook | Category | Event | What It Does | Key Feature |
|------|----------|-------|-------------|-------------|
| **bash-guard.sh** | Safety | PreToolUse | Blocks `rm`, enforces tmux for dev servers, gates PR creation | Subagent-aware (warns instead of blocking) |
| **secret-guard.sh** | Safety | UserPromptSubmit | Detects API keys, tokens, PEM keys in messages | 6 secret pattern categories |
| **edit-guard.sh** | Safety | PostToolUse | Checks README language separation, API signature changes | Reminds to grep all callers |
| **auto-commit.sh** | Workflow | Stop | Blocks session end if repos have uncommitted changes | Anti-loop: max 2 blocks per session |
| **track-edit.sh** | Workflow | PreToolUse | Records which repos are modified via Edit/Write | Feeds into auto-commit tracking |
| **nag-reminder.sh** | Workflow | PostToolUse | Detects behavior drift in multi-step tasks | Configurable threshold via `CC_NAG_THRESHOLD` |
| **load-context.sh** | Lifecycle | SessionStart | Injects identity and service status at session start | Customizable via env vars |
| **session-summary.sh** | Lifecycle | Stop | Generates indexed session summaries | Learning pattern detection |
| **pre-compact.sh** | Lifecycle | PreCompact | Saves critical context before compact | Recovery breadcrumb files |
| **ts-check.sh** | Quality | PostToolUse | Runs TypeScript/syntax checks after edits | Auto-detects project root and check scripts |
| **rating-capture.sh** | Feedback | UserPromptSubmit | Captures 1-10 ratings to JSONL | Smart false-positive filtering |
| **repos.conf** | Config | -- | Shared repo list for tracking hooks | Single source of truth |

---

## Architecture

### Hook Profile System

Every hook supports a unified enable/disable mechanism -- no need to edit `settings.json` to toggle hooks on and off:

```bash
# Disable ALL hooks instantly (e.g., during a quick one-off task)
export CC_HOOK_PROFILE=off

# Disable specific hooks by filename
export CC_DISABLED_HOOKS="nag-reminder.sh,ts-check.sh"
```

This works because every hook starts with the same guard:

```bash
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac
```

### Environment Variables

All hooks are configurable without editing source code:

| Variable | Default | Used By |
|----------|---------|---------|
| `CC_HOOK_PROFILE` | `standard` | All hooks -- set to `off` to disable |
| `CC_DISABLED_HOOKS` | (empty) | All hooks -- comma-separated filenames |
| `CC_GITHUB_OWNERS` | (empty) | bash-guard -- your GitHub usernames/orgs |
| `CC_NAG_THRESHOLD` | `5` | nag-reminder -- tool calls before reminder |
| `CC_SESSION_INDEX` | `~/.claude/session-index.md` | session-summary -- output file |
| `CC_RATINGS_FILE` | `~/.claude/ratings.jsonl` | rating-capture -- ratings output |
| `CC_PACKAGE_RUNNER` | `npx` | ts-check -- package runner (npx/bun/pnpm) |
| `CC_MEMORY_DIR` | `~/.claude/memory` | load-context -- memory directory |
| `CC_IDENTITY_SUMMARY` | (template) | load-context -- your identity one-liner |
| `CC_CHECKLIST_PATTERN` | `~/Desktop/*checklist*.md` | pre-compact -- checklist glob pattern |

### Per-Session Tracking

The workflow hooks (`bash-guard`, `track-edit`, `auto-commit`) work together through per-session tracking files:

```
bash-guard.sh ──┐
                ├──▶ /tmp/cc-session-repos-{SESSION_ID}  ──▶ auto-commit.sh
track-edit.sh ──┘
```

1. `bash-guard.sh` and `track-edit.sh` record which repos are touched during a session
2. `auto-commit.sh` reads that list at session end and checks for uncommitted changes
3. If changes exist, it blocks Claude from stopping until they're committed

This design means multiple Claude sessions running in parallel don't interfere with each other.

---

## Settings Template

The `settings-template.json` maps each hook to its lifecycle event. Here's what it looks like:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/safety/bash-guard.sh" }]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/workflow/track-edit.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/quality/ts-check.sh 2>&1 | head -20" }]
      },
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/safety/edit-guard.sh" }]
      },
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/workflow/nag-reminder.sh" }]
      }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/safety/secret-guard.sh" }] },
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/feedback/rating-capture.sh" }] }
    ],
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/lifecycle/load-context.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/lifecycle/session-summary.sh 2>&1 | head -30" }] },
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/workflow/auto-commit.sh 2>&1 | head -30" }] }
    ],
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/lifecycle/pre-compact.sh" }] }
    ]
  }
}
```

See [`settings-template.json`](settings-template.json) for the full, copy-paste-ready version.

---

## Why These Hooks

These are not toy examples. They emerged from solving real problems:

- **bash-guard.sh** exists because `rm -rf` happened one too many times. The subagent detection was added after discovering that Claude's sub-agents bypass permission checks but not hooks.

- **auto-commit.sh** was born from repeatedly ending sessions with uncommitted code. The anti-loop mechanism (max 2 blocks) prevents infinite "block -> attempt commit -> fail -> block" cycles.

- **nag-reminder.sh** addresses a real behavior pattern: Claude gets focused on executing and forgets to observe results. The ReAct observation tracking catches this drift.

- **secret-guard.sh** catches the moment you accidentally paste an API key into a prompt. Six regex patterns cover OpenAI, Anthropic, GitHub, AWS, Slack tokens, and PEM keys.

- **session-summary.sh** automatically builds a searchable index of what happened in each session, including learning pattern detection (error->fix cycles, explicit "remember this" signals).

- **pre-compact.sh** saves your active state before Claude Code compacts the conversation, so you don't lose track of what you were doing.

The Hook Profile system (inspired by [ECC](https://github.com/anthropics/ecc)) lets you instantly toggle hooks via environment variables -- no config file editing needed.

---

## Documentation

- [Hook Lifecycle Reference](docs/hook-lifecycle.md) -- All 6 events, stdin/stdout/stderr behavior, exit codes, debugging tips

---

## Contributing

Found a useful hook pattern? PRs welcome. Each hook should:

1. Include the Hook Profile guard at the top
2. Read stdin (even if unused)
3. Document its trigger event and I/O behavior
4. Be tested manually before submitting

---

## License

MIT

---

## See Also

- [cc-rules-cookbook](https://github.com/AliceLJY/cc-rules-cookbook) -- Companion repo: CLAUDE.md rules and project configuration patterns
