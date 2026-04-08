<p align="center"><a href="README.md">🇬🇧 English</a></p>

# cc-hooks-gallery

**500+ 场实战打磨的 Claude Code Hook 集合**

[![Hooks](https://img.shields.io/badge/hooks-12-blue)](#hook-目录)
[![Lifecycle Events](https://img.shields.io/badge/lifecycle_events-6-green)](#hook-生命周期)
[![License](https://img.shields.io/badge/license-MIT-orange)](LICENSE)

每一个 hook 都来自真实的日常使用，不是纸上谈兵的示例，而是在数百次 Claude Code 会话中踩坑后沉淀下来的解决方案。涵盖安全防护、工作流自动化和生产力提升。

---

## Hook 生命周期

Claude Code 在 6 个生命周期节点触发 hook，整体流程如下：

```
                         cc-hooks-gallery 覆盖范围
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

每个 hook 都是独立的 bash 脚本，通过 stdin 接收 JSON，stdout 注入 Claude 上下文，stderr 展示给用户。退出码 `2` = 阻止当前操作。

---

## 快速开始

```bash
# 克隆并安装
git clone https://github.com/AliceLJY/cc-hooks-gallery.git
cd cc-hooks-gallery
bash install.sh           # 交互式：选择要启用的 hook
bash install.sh --all     # 一把梭，全部安装
bash install.sh --dry-run # 预览模式，不做实际修改
```

安装器会备份你现有的 `settings.json`，把 hook 复制到 `~/.claude/hooks/`，然后合并配置。

---

## Hook 目录

| Hook | 分类 | 触发事件 | 功能 | 亮点 |
|------|------|---------|------|------|
| **bash-guard.sh** | 安全 | PreToolUse | 拦截 `rm`、强制 tmux 跑 dev server、管控 PR 创建 | 子 agent 感知（对子 agent 只警告不拦截） |
| **secret-guard.sh** | 安全 | UserPromptSubmit | 检测消息中的 API key、token、PEM 密钥 | 覆盖 6 大类密钥模式 |
| **edit-guard.sh** | 安全 | PostToolUse | 检查 README 语言分离、API 签名变更 | 提醒 grep 所有调用方 |
| **auto-commit.sh** | 工作流 | Stop | 有未提交的变更时阻止会话结束 | 防死循环：每次会话最多阻止 2 次 |
| **track-edit.sh** | 工作流 | PreToolUse | 记录哪些仓库通过 Edit/Write 被修改 | 为 auto-commit 提供跟踪数据 |
| **nag-reminder.sh** | 工作流 | PostToolUse | 检测多步任务中的行为偏移 | 通过 `CC_NAG_THRESHOLD` 配置触发阈值 |
| **load-context.sh** | 生命周期 | SessionStart | 会话启动时注入身份信息和服务状态 | 支持环境变量自定义 |
| **session-summary.sh** | 生命周期 | Stop | 生成可检索的会话摘要索引 | 自动识别学习模式 |
| **pre-compact.sh** | 生命周期 | PreCompact | compact 前保存关键上下文 | 生成恢复用的面包屑文件 |
| **ts-check.sh** | 质量 | PostToolUse | 编辑后自动运行 TypeScript/语法检查 | 自动检测项目根目录和检查脚本 |
| **rating-capture.sh** | 反馈 | UserPromptSubmit | 捕获 1-10 评分到 JSONL | 智能过滤误判 |
| **repos.conf** | 配置 | -- | 多个跟踪 hook 共享的仓库列表 | 单一事实来源 |

---

## 架构设计

### Hook Profile 机制

每个 hook 都内置了统一的开关机制，不需要改 `settings.json` 就能控制 hook 的启停：

```bash
# 一键关闭所有 hook（比如临时做个快活儿不想被打扰）
export CC_HOOK_PROFILE=off

# 按文件名禁用特定 hook
export CC_DISABLED_HOOKS="nag-reminder.sh,ts-check.sh"
```

能这样用是因为每个 hook 开头都有同一段守卫代码：

```bash
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac
```

### 环境变量

所有 hook 都可以通过环境变量配置，不用改源码：

| 变量 | 默认值 | 使用者 |
|------|--------|--------|
| `CC_HOOK_PROFILE` | `standard` | 所有 hook -- 设为 `off` 即全部禁用 |
| `CC_DISABLED_HOOKS` | (空) | 所有 hook -- 逗号分隔的文件名 |
| `CC_GITHUB_OWNERS` | (空) | bash-guard -- 你的 GitHub 用户名/组织 |
| `CC_NAG_THRESHOLD` | `5` | nag-reminder -- 多少次工具调用后触发提醒 |
| `CC_SESSION_INDEX` | `~/.claude/session-index.md` | session-summary -- 输出文件路径 |
| `CC_RATINGS_FILE` | `~/.claude/ratings.jsonl` | rating-capture -- 评分输出文件 |
| `CC_PACKAGE_RUNNER` | `npx` | ts-check -- 包运行器 (npx/bun/pnpm) |
| `CC_MEMORY_DIR` | `~/.claude/memory` | load-context -- 记忆目录 |
| `CC_IDENTITY_SUMMARY` | (模板) | load-context -- 你的身份一句话描述 |
| `CC_CHECKLIST_PATTERN` | `~/Desktop/*checklist*.md` | pre-compact -- checklist 文件的 glob 匹配 |

### 会话级跟踪

工作流 hook（`bash-guard`、`track-edit`、`auto-commit`）通过会话级跟踪文件协作：

```
bash-guard.sh ──┐
                ├──▶ /tmp/cc-session-repos-{SESSION_ID}  ──▶ auto-commit.sh
track-edit.sh ──┘
```

1. `bash-guard.sh` 和 `track-edit.sh` 记录会话中涉及了哪些仓库
2. `auto-commit.sh` 在会话结束时读取这个列表，检查是否有未提交的变更
3. 如果有未提交的变更，会阻止 Claude 结束会话，直到变更被提交

这个设计让多个并行运行的 Claude 会话互不干扰。

---

## Settings 模板

`settings-template.json` 把每个 hook 映射到对应的生命周期事件，长这样：

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

完整的可直接复制使用的版本见 [`settings-template.json`](settings-template.json)。

---

## 为什么是这些 Hook

这些不是玩具示例，每一个都是从真实问题中长出来的：

- **bash-guard.sh** -- 因为 `rm -rf` 翻过车。子 agent 检测是后来加的，起因是发现 Claude 的子 agent 会绕过权限检查，但绕不过 hook。

- **auto-commit.sh** -- 反复在会话结束时忘记提交代码，忍无可忍搞了这个。防死循环机制（最多阻止 2 次）是为了避免"阻止 -> 尝试提交 -> 失败 -> 继续阻止"的无限循环。

- **nag-reminder.sh** -- Claude 有个真实的行为模式：执行时太专注，忘了回头看结果。ReAct 观察追踪机制就是为了抓住这种偏移。

- **secret-guard.sh** -- 总有手滑把 API key 粘贴到 prompt 里的时候。6 套正则覆盖 OpenAI、Anthropic、GitHub、AWS、Slack token 和 PEM 密钥。

- **session-summary.sh** -- 自动构建每次会话的可搜索索引，还能识别学习模式（比如 error->fix 循环、显式的"记住这个"信号）。

- **pre-compact.sh** -- Claude Code compact 对话时会丢失当前状态，这个 hook 提前保存，避免你丢失工作进度。

Hook Profile 机制（灵感来自 [ECC](https://github.com/anthropics/ecc)）让你用环境变量就能即时切换 hook，不用改配置文件。

---

## 文档

- [Hook 生命周期参考](docs/hook-lifecycle.md) -- 6 个事件的完整说明、stdin/stdout/stderr 行为、退出码、调试技巧

---

## 贡献

发现了好用的 hook 模式？欢迎提 PR。每个 hook 需要：

1. 文件顶部包含 Hook Profile 守卫代码
2. 读取 stdin（即使不用）
3. 注明触发事件和 I/O 行为
4. 提交前手动测试通过

---

## License

MIT

---

## 相关项目

- [cc-rules-cookbook](https://github.com/AliceLJY/cc-rules-cookbook) -- 姊妹仓库：CLAUDE.md 规则和项目配置模式
