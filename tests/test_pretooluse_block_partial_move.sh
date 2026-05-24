#!/bin/bash
# Smoke tests for hooks/pretooluse-block-partial-move.sh.
# Pipes mock PreToolUse JSON; verifies exit codes + stderr.
# NOTE: do NOT add `set -e` — subtests 2 and 3 expect the hook to exit
# with code 2 (block), and `set -e` would silently kill the test script
# via `OUT=$(... | bash "$HOOK" ...); CODE=$?` before the assertion runs.

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/pretooluse-block-partial-move.sh"
[ -x "$HOOK" ] || { echo "FAIL: hook not executable: $HOOK"; exit 1; }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t 'plan-eval-test')
trap "rm -rf '$TMP'" EXIT

mkdir -p "$TMP/docs/superpowers/plans/partial" "$TMP/docs/superpowers/plans/completed"

# Plan WITH valid Evaluator (section + code block inside)
cat > "$TMP/docs/superpowers/plans/partial/2026-01-01-good-plan.md" <<'EOF'
# Good Plan Implementation Plan
## Tasks
do stuff
## Evaluator
```bash
pytest tests/foo.py::test_bar -v
```
Expected: PASS.
EOF

# Plan WITHOUT Evaluator section
cat > "$TMP/docs/superpowers/plans/partial/2026-01-01-bad-plan.md" <<'EOF'
# Bad Plan Implementation Plan
## Tasks
do stuff
## Rollback
revert
EOF

# Plan with Evaluator heading but EMPTY (no code block)
cat > "$TMP/docs/superpowers/plans/partial/2026-01-01-empty-eval.md" <<'EOF'
# Empty Eval Implementation Plan
## Tasks
do stuff
## Evaluator
maybe run a test idk
## Rollback
revert
EOF

# --- Subtest 1: PASS — plan has valid Evaluator ---
INPUT='{"tool_input":{"command":"git mv '"$TMP"'/docs/superpowers/plans/partial/2026-01-01-good-plan.md '"$TMP"'/docs/superpowers/plans/completed/2026-01-01-good-plan.md"}}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1); CODE=$?
[ "$CODE" = "0" ] || { echo "FAIL subtest1: expected exit 0 (PASS), got $CODE"; echo "out: $OUT"; exit 1; }
echo "PASS subtest1: plan with valid Evaluator allowed"

# --- Subtest 2: BLOCK — plan has no Evaluator section ---
INPUT='{"tool_input":{"command":"git mv '"$TMP"'/docs/superpowers/plans/partial/2026-01-01-bad-plan.md '"$TMP"'/docs/superpowers/plans/completed/2026-01-01-bad-plan.md"}}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1); CODE=$?
[ "$CODE" = "2" ] || { echo "FAIL subtest2: expected exit 2 (BLOCK), got $CODE"; echo "out: $OUT"; exit 1; }
echo "$OUT" | grep -q "no top-level" || { echo "FAIL subtest2: missing 'no top-level' in message"; echo "out: $OUT"; exit 1; }
echo "PASS subtest2: plan without Evaluator blocked"

# --- Subtest 3: BLOCK — plan has Evaluator but no code block ---
INPUT='{"tool_input":{"command":"git mv '"$TMP"'/docs/superpowers/plans/partial/2026-01-01-empty-eval.md '"$TMP"'/docs/superpowers/plans/completed/2026-01-01-empty-eval.md"}}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1); CODE=$?
[ "$CODE" = "2" ] || { echo "FAIL subtest3: expected exit 2 (BLOCK), got $CODE"; echo "out: $OUT"; exit 1; }
echo "$OUT" | grep -q "no runnable check" || { echo "FAIL subtest3: missing 'no runnable check' in message"; echo "out: $OUT"; exit 1; }
echo "PASS subtest3: plan with empty Evaluator blocked"

# --- Subtest 4: PASS — non-matching command (not a git mv) ---
INPUT='{"tool_input":{"command":"ls /tmp"}}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1); CODE=$?
[ "$CODE" = "0" ] || { echo "FAIL subtest4: non-matching cmd should be exit 0, got $CODE"; exit 1; }
echo "PASS subtest4: non-matching commands not affected"

# --- Subtest 5: PASS — bypass env honored ---
export PLAN_EVALUATOR_GATE_BYPASS=1
INPUT='{"tool_input":{"command":"git mv '"$TMP"'/docs/superpowers/plans/partial/2026-01-01-bad-plan.md '"$TMP"'/docs/superpowers/plans/completed/2026-01-01-bad-plan.md"}}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1); CODE=$?
[ "$CODE" = "0" ] || { echo "FAIL subtest5: bypass env should allow, got $CODE"; exit 1; }
unset PLAN_EVALUATOR_GATE_BYPASS
echo "PASS subtest5: PLAN_EVALUATOR_GATE_BYPASS=1 allows"

echo ""
echo "All plan-evaluator-gate hook tests pass."
exit 0
