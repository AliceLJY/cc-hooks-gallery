#!/bin/bash
# install.sh -- cc-hooks-gallery installer
# Copies hooks into ~/.claude/hooks/ and merges config into settings.json
#
# Usage:
#   bash install.sh              # Interactive mode (choose which hooks to enable)
#   bash install.sh --all        # Install all hooks
#   bash install.sh --dry-run    # Show what would be done without making changes

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/hooks"
HOOKS_DST="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
SETTINGS_TEMPLATE="$SCRIPT_DIR/settings-template.json"
DRY_RUN=0
INSTALL_ALL=0

# Parse args
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=1 ;;
        --all) INSTALL_ALL=1 ;;
        --help|-h)
            echo "Usage: bash install.sh [--all] [--dry-run] [--help]"
            echo ""
            echo "Options:"
            echo "  --all       Install all hooks without prompting"
            echo "  --dry-run   Show what would be done without making changes"
            echo "  --help      Show this help message"
            exit 0
            ;;
    esac
done

echo -e "${BLUE}cc-hooks-gallery installer${NC}"
echo "=================================="
echo ""

# ===== Step 1: Create hooks directory =====
echo -e "${GREEN}[1/4]${NC} Preparing hooks directory..."
if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would create: $HOOKS_DST/{safety,workflow,lifecycle,quality,feedback}"
else
    mkdir -p "$HOOKS_DST"/{safety,workflow,lifecycle,quality,feedback}
    echo "  Created: $HOOKS_DST/"
fi

# ===== Step 2: List available hooks =====
echo ""
echo -e "${GREEN}[2/4]${NC} Available hooks:"
echo ""

declare -A HOOK_DESCRIPTIONS=(
    ["safety/bash-guard.sh"]="Block dangerous commands (rm, dev servers outside tmux, PR checks)"
    ["safety/secret-guard.sh"]="Detect API keys/secrets in user messages before sending"
    ["safety/edit-guard.sh"]="Check README language separation + API signature change reminders"
    ["workflow/auto-commit.sh"]="Block session end if tracked repos have uncommitted changes"
    ["workflow/track-edit.sh"]="Track which repos are modified via Edit/Write tools"
    ["workflow/nag-reminder.sh"]="Remind to write observation notes during multi-step tasks"
    ["lifecycle/load-context.sh"]="Inject identity/project context at session start"
    ["lifecycle/session-summary.sh"]="Generate session index entries for later retrieval"
    ["lifecycle/pre-compact.sh"]="Save critical context before compact to prevent loss"
    ["quality/ts-check.sh"]="Run TypeScript/syntax checks after editing code files"
    ["feedback/rating-capture.sh"]="Capture 1-10 ratings from user messages into JSONL"
)

HOOKS_TO_INSTALL=()
i=1
declare -A HOOK_INDEX

for hook in \
    "safety/bash-guard.sh" \
    "safety/secret-guard.sh" \
    "safety/edit-guard.sh" \
    "workflow/auto-commit.sh" \
    "workflow/track-edit.sh" \
    "workflow/nag-reminder.sh" \
    "lifecycle/load-context.sh" \
    "lifecycle/session-summary.sh" \
    "lifecycle/pre-compact.sh" \
    "quality/ts-check.sh" \
    "feedback/rating-capture.sh"; do
    desc="${HOOK_DESCRIPTIONS[$hook]}"
    printf "  ${YELLOW}%2d${NC}. %-35s %s\n" "$i" "$hook" "$desc"
    HOOK_INDEX[$i]="$hook"
    ((i++))
done

echo ""

# ===== Step 3: Select hooks =====
if [ "$INSTALL_ALL" -eq 1 ]; then
    for key in $(seq 1 $((i-1))); do
        HOOKS_TO_INSTALL+=("${HOOK_INDEX[$key]}")
    done
    echo "  Installing all hooks."
else
    echo -e "Enter hook numbers to install (space-separated), ${YELLOW}all${NC} for everything, or ${YELLOW}q${NC} to quit:"
    read -r -p "  > " SELECTION

    if [ "$SELECTION" = "q" ]; then
        echo "Aborted."
        exit 0
    elif [ "$SELECTION" = "all" ]; then
        for key in $(seq 1 $((i-1))); do
            HOOKS_TO_INSTALL+=("${HOOK_INDEX[$key]}")
        done
    else
        for num in $SELECTION; do
            if [[ -n "${HOOK_INDEX[$num]:-}" ]]; then
                HOOKS_TO_INSTALL+=("${HOOK_INDEX[$num]}")
            else
                echo -e "  ${RED}Warning: Invalid number $num, skipping${NC}"
            fi
        done
    fi
fi

if [ ${#HOOKS_TO_INSTALL[@]} -eq 0 ]; then
    echo "No hooks selected. Exiting."
    exit 0
fi

echo ""
echo -e "${GREEN}[3/4]${NC} Installing ${#HOOKS_TO_INSTALL[@]} hooks..."

# Copy selected hooks
for hook in "${HOOKS_TO_INSTALL[@]}"; do
    SRC="$HOOKS_SRC/$hook"
    DST="$HOOKS_DST/$hook"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  Would copy: $hook"
    else
        cp "$SRC" "$DST"
        chmod +x "$DST"
        echo "  Installed: $hook"
    fi
done

# Always copy repos.conf template if workflow hooks are selected
for hook in "${HOOKS_TO_INSTALL[@]}"; do
    if [[ "$hook" == workflow/* ]]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  Would copy: repos.conf (template)"
        elif [ ! -f "$HOOKS_DST/repos.conf" ]; then
            cp "$HOOKS_SRC/repos.conf" "$HOOKS_DST/repos.conf"
            echo "  Installed: repos.conf (edit this to add your repos)"
        fi
        break
    fi
done

# ===== Step 4: Merge settings =====
echo ""
echo -e "${GREEN}[4/4]${NC} Configuring settings.json..."

if [ "$DRY_RUN" -eq 1 ]; then
    echo "  Would merge hook config into $SETTINGS_FILE"
    echo ""
    echo -e "${BLUE}Dry run complete.${NC} No changes were made."
    exit 0
fi

if [ -f "$SETTINGS_FILE" ]; then
    # Backup existing settings
    BACKUP="${SETTINGS_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP"
    echo "  Backed up: $BACKUP"

    # Check if hooks section already exists
    if python3 -c "import json; d=json.load(open('$SETTINGS_FILE')); assert 'hooks' in d" 2>/dev/null; then
        echo ""
        echo -e "  ${YELLOW}Warning:${NC} settings.json already has a 'hooks' section."
        echo "  The template has been saved to: $SETTINGS_TEMPLATE"
        echo "  Please merge manually to avoid overwriting your existing hooks."
        echo ""
        echo "  You can review the template with:"
        echo "    cat $SETTINGS_TEMPLATE"
    else
        # No existing hooks -> safe to merge
        python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    settings = json.load(f)
with open('$SETTINGS_TEMPLATE') as f:
    template = json.load(f)
# Remove comments
template.pop('\$schema', None)
template.pop('_comment', None)
settings['hooks'] = template['hooks']
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
print('  Merged hooks config into settings.json')
" 2>/dev/null || {
            echo -e "  ${RED}Failed to merge automatically.${NC}"
            echo "  Please manually merge from: $SETTINGS_TEMPLATE"
        }
    fi
else
    # No settings.json exists -> create from template
    python3 -c "
import json
with open('$SETTINGS_TEMPLATE') as f:
    template = json.load(f)
template.pop('\$schema', None)
template.pop('_comment', None)
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(template, f, indent=2)
print('  Created settings.json with hooks config')
" 2>/dev/null
fi

echo ""
echo "=================================="
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit $HOOKS_DST/repos.conf to add your repos (for auto-commit)"
echo "  2. Edit $HOOKS_DST/lifecycle/load-context.sh to set your identity"
echo "  3. Set CC_IDENTITY_SUMMARY env var or edit the file directly"
echo ""
echo "Environment variables you can customize:"
echo "  CC_HOOK_PROFILE=off          Disable all hooks"
echo "  CC_DISABLED_HOOKS=hook1,hook2 Disable specific hooks"
echo "  CC_GITHUB_OWNERS=user1,user2  Your GitHub orgs (for PR guard)"
echo "  CC_NAG_THRESHOLD=5            Tool calls before nag reminder"
echo "  CC_SESSION_INDEX=path          Custom session index file path"
echo "  CC_RATINGS_FILE=path           Custom ratings file path"
echo "  CC_PACKAGE_RUNNER=npx          Package runner (npx/bun/pnpm)"
echo "  CC_MEMORY_DIR=path             Memory directory path"
echo "  CC_IDENTITY_SUMMARY=\"...\"      Your one-line identity summary"
echo ""
echo "Test a hook: echo '{}' | bash ~/.claude/hooks/safety/bash-guard.sh"
