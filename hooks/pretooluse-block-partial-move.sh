#!/bin/bash
# plan-evaluator-gate — opt-in PreToolUse hook.
# Blocks `git mv .../partial/<plan>.md .../completed/...` when the source plan
# lacks a top-level `## Evaluator` section with at least one runnable check.
#
# Wire up in your project's .claude/settings.json — see plugin README.
# Bypass: PLAN_EVALUATOR_GATE_BYPASS=1

set -uo pipefail

# Bypass via env
[ "${PLAN_EVALUATOR_GATE_BYPASS:-}" = "1" ] && exit 0

# Parse command from PreToolUse stdin JSON
INPUT=$(cat)
CMD=$(echo "$INPUT" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Only fire on `git mv .../partial/... .../completed/...` (forward or backward slash)
case "$CMD" in
  *"git mv"*"partial/"*"completed/"*) ;;
  *"git mv"*'partial\'*'completed\'*) ;;
  *) exit 0 ;;
esac

# Extract source plan path (the .md file under partial/)
PLAN=$(echo "$CMD" | python -c "
import sys, re
cmd = sys.stdin.read()
# Match git mv <anything>/partial/<plan>.md ...
m = re.search(r'git\s+mv\s+(\S*[/\\\\]partial[/\\\\][^\s]+\.md)\s+', cmd)
if m:
    print(m.group(1))
" 2>/dev/null)
[ -z "$PLAN" ] && exit 0
[ ! -f "$PLAN" ] && exit 0

# Verify ## Evaluator section + at least one fenced code block inside it
python - "$PLAN" <<'PY'
import sys, re
plan_path = sys.argv[1]
with open(plan_path, encoding='utf-8') as f:
    content = f.read()

# Find top-level `## Evaluator` (or `## Evaluator spec`) — body runs until next `## ` or EOF
m = re.search(
    r'^## Evaluator(?:\s+spec)?\s*$(.*?)(?=^## |\Z)',
    content,
    re.MULTILINE | re.DOTALL,
)

if not m:
    sys.stderr.write(
        f"[plan-evaluator-gate] BLOCKED: plan '{plan_path}' has no top-level '## Evaluator' section.\n"
        "Add one with a concrete check (test command, curl assertion, query, skill invocation, or rubric)\n"
        "before moving to completed/. See plan-evaluator-gate SKILL.md for acceptable forms.\n"
        "Bypass (intentional): PLAN_EVALUATOR_GATE_BYPASS=1\n"
    )
    sys.exit(2)

body = m.group(1)
if '```' not in body:
    sys.stderr.write(
        f"[plan-evaluator-gate] BLOCKED: plan '{plan_path}' has '## Evaluator' but no runnable check.\n"
        "Declare a concrete check (test command, curl, query, skill, or rubric) inside the section\n"
        "using a fenced code block. See plan-evaluator-gate SKILL.md for examples.\n"
        "Bypass (intentional): PLAN_EVALUATOR_GATE_BYPASS=1\n"
    )
    sys.exit(2)

sys.exit(0)
PY
