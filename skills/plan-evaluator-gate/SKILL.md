---
name: plan-evaluator-gate
description: Use BEFORE moving a writing-plans plan from partial/ to completed/, before writing a CHANGELOG entry that closes a plan, or before marking a plan-tracking ticket complete. Greps the plan for a top-level `## Evaluator` section with at least one runnable check; returns BLOCK with remediation guidance if absent, PASS otherwise. Companion to obra/superpowers writing-plans.
---

# Plan Evaluator Gate

## Overview

Companion to `superpowers:writing-plans`. Plans without a deterministic Evaluator drift into "looks done = is done" thinking — a maintainer reads the implementation, decides it looks right, moves the plan to `completed/`, and weeks later a regression surfaces with no record of what "passing" was supposed to mean.

This skill enforces the **Planner → Generator → Evaluator** topology at the lifecycle-transition boundary. The Planner (`superpowers:writing-plans`) writes the spec including the Evaluator, the Generator (`superpowers:executing-plans` / `superpowers:subagent-driven-development`) executes one task at a time, and this gate verifies the Evaluator exists before allowing the partial → completed move.

## When to invoke

Invoke this skill **BEFORE**:

- `git mv docs/superpowers/plans/partial/<plan>.md docs/superpowers/plans/completed/<plan>.md` (or equivalent lifecycle path)
- Writing a CHANGELOG entry that closes a plan
- Marking the plan's tracking ticket complete in IMPROVEMENTS.md / a project tracker
- Including "plan complete" / "all tasks shipped" / "verified end-to-end" claims in a PR body that closes the plan

If you're not sure whether you're about to close a plan, err on the side of invoking — the skill is read-only and returns quickly.

## Verification logic

1. Read the plan markdown file.
2. Find a top-level `## Evaluator` heading (or `## Evaluator spec`) — must be `##`, not `###` or deeper, so the gate is grep-discoverable across the plan corpus.
3. Verify the section body (everything until the next `## ` heading or EOF) contains at least one fenced code block (` ``` ` triple-backtick).
4. Return:
   - **PASS** if both checks succeed.
   - **BLOCK** with the specific failure (missing section OR empty section) and a one-line remediation pointer.

## Acceptable Evaluator forms

Mirrors the upstream writing-plans pattern (see [obra/superpowers#1627](https://github.com/obra/superpowers/pull/1627)):

- **Test command** — `pytest path::test_function`, `npx playwright test specs/<feature>.spec.ts`, `cargo test <name>`, `go test ./pkg/...` — that exits 0
- **HTTP assertion** — `curl -fsS <url>` with expected status + body shape against a deployed endpoint
- **Database query** — a SELECT (or equivalent) asserting expected state after the plan runs
- **Skill invocation** — a project-local `verify-*` skill that returns success
- **Rubric pass-list** — N/N criteria met by manual inspection, for AI-system or design plans where a deterministic check isn't possible

## Example

A plan that **PASSES** the gate:

````markdown
## Evaluator

```bash
pytest tests/auth/test_session_refresh.py::test_token_rotation -v
```

Expected: PASS. Verifies the refresh-token rotation flow returns a new access
token, invalidates the old refresh token, and writes the rotation event to
the audit log.
````

A plan that **BLOCKS**:

```markdown
## Tasks
[... tasks ...]

## Rollback
[... rollback steps ...]
```

→ BLOCKED: no `## Evaluator` section. Add one with a concrete check before marking complete.

## Strict-mode hook (optional)

For teams that want enforcement at the `git mv` boundary (not just Claude's discipline), this plugin ships an opt-in PreToolUse hook. Add to your `.claude/settings.json` (user-scope install path — the default):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOME/.claude/plugins/cache/plan-evaluator-gate/plan-evaluator-gate/0.1.0/hooks/pretooluse-block-partial-move.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

For project-scope installs, swap `$HOME` for `$CLAUDE_PROJECT_DIR`. After a plugin upgrade, run `claude plugin details plan-evaluator-gate@plan-evaluator-gate` to find the new version segment and update the hook path.

The hook fires on any `git mv .../partial/<plan>.md .../completed/...` command, reads the source plan, runs the same verification logic, and exits 2 (block) if the gate fails. Bypass via env `PLAN_EVALUATOR_GATE_BYPASS=1` for intentional exceptions.

## What this skill does NOT do

- Doesn't replace `superpowers:writing-plans` — install both
- Doesn't enforce plan QUALITY (placeholder scan, type consistency, etc. — that's writing-plans Self-Review)
- Doesn't auto-create the Evaluator section — that's the planner's job; this is the gate, not the generator
- Doesn't verify the Evaluator actually PASSES — only that it's declared with a concrete check; the human / Claude still runs it

## Why this exists

The Evaluator pattern was originally formalized at the project level in [mw-vastra PR #488](https://github.com/ministerwhite/mw-vastra/pull/488). Upstream PR [obra/superpowers#1627](https://github.com/obra/superpowers/pull/1627) proposes folding the Evaluator section directly into `writing-plans` SKILL.md. If/when that merges, this plugin becomes redundant — uninstall it and rely on the upstream pattern.

Until then, this plugin lets any Claude Code user adopt the gate without waiting on the upstream review cycle.
