#!/bin/bash
# edit-guard.sh -- PostToolUse: Edit/Write quality gatekeeper
# Promotes paper rules into automated checks:
#
# Check 1: README bilingual separation (README.md = English, README_CN.md = Chinese)
# Check 2: Function/API signature changes -> remind to grep all call sites
#
# Trigger: PostToolUse (Edit|Write)
# Output: stderr -> soft reminder injected into Claude context (no hard block)
# 2026-03-30 created

# === Hook Profile control ===
[ "${CC_HOOK_PROFILE:-standard}" = "off" ] && exit 0
case ",${CC_DISABLED_HOOKS}," in *",$(basename "$0"),"*) exit 0 ;; esac

INPUT=$(cat)
[[ -z "$INPUT" ]] && exit 0

# Use python3 for all checks (handles special chars safely, macOS compatible)
printf '%s' "$INPUT" | python3 -c '
import sys, json, re, os

data = json.loads(sys.stdin.read())
ti = data.get("tool_input", {})
file_path = ti.get("file_path", "")
old_string = ti.get("old_string", "")
new_string = ti.get("new_string", "")

if not file_path:
    sys.exit(0)

basename = os.path.basename(file_path)
warnings = []

# ========== CHECK 1: README bilingual separation ==========
if basename == "README.md" and os.path.isfile(file_path):
    try:
        text = open(file_path, encoding="utf-8").read()
        if re.search(r"[\u4e00-\u9fff]", text):
            warnings.append(
                "[README-GUARD] Chinese content detected in README.md!\n"
                "  Rule: README.md must be English-only; Chinese goes to README_CN.md\n"
                "  Fix: Move Chinese content to README_CN.md in the same directory"
            )
    except Exception:
        pass

elif basename == "README_CN.md" and os.path.isfile(file_path):
    try:
        text = open(file_path, encoding="utf-8").read()
        cn_count = len(re.findall(r"[\u4e00-\u9fff]", text))
        if cn_count < 10 and len(text) > 100:
            warnings.append(
                "[README-GUARD] README_CN.md has almost no Chinese!\n"
                "  Rule: README_CN.md should be the Chinese version"
            )
    except Exception:
        pass

# ========== CHECK 2: Function signature change -> remind to grep call sites ==========
code_exts = (".ts", ".js", ".tsx", ".jsx", ".py", ".go", ".rs", ".java")
if any(file_path.endswith(ext) for ext in code_exts) and old_string:
    sig_patterns = [
        r"(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\([^)]*\)",
        r"def\s+(\w+)\s*\([^)]*\)",
        r"class\s+(\w+)",
        r"(?:public|private|protected)\s+(?:static\s+)?(?:async\s+)?(\w+)\s*\([^)]*\)",
    ]
    for line in old_string.split("\n"):
        matched = False
        for p in sig_patterns:
            m = re.search(p, line.strip())
            if m:
                func_name = m.group(1)
                sig_line = line.strip()
                # Check if the same line exists unchanged in new_string
                if sig_line not in (new_string or ""):
                    warnings.append(
                        f"[API-GUARD] Function/API signature change detected: {func_name}\n"
                        f"  Rule: After changing an API, grep all call sites for compatibility\n"
                        f"  Suggested: Grep \"{func_name}\" to check all callers need updating"
                    )
                matched = True
                break
        if matched:
            break

if warnings:
    for w in warnings:
        print(w, file=sys.stderr)
' 2>/dev/null

exit 0
