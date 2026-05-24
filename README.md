# plan-evaluator-gate

Companion Claude Code plugin for the [`superpowers:writing-plans`](https://github.com/obra/superpowers/tree/main/skills/writing-plans) skill. Enforces the **Planner → Generator → Evaluator** topology by gating the `partial/` → `completed/` plan-lifecycle transition behind a declared, runnable Evaluator.

## Why

Plans without a deterministic Evaluator drift into "looks done = is done" thinking. A maintainer reads the implementation, decides it looks right, moves the plan to `completed/`. Weeks later a regression surfaces and there's no record of what "passing" was supposed to mean.

This plugin makes the completion gate **runnable**:

- The **skill** (`plan-evaluator-gate`) is invoked when Claude is about to mark a plan complete; it greps for `## Evaluator` and returns BLOCK if absent.
- The **optional PreToolUse hook** enforces the gate at the `git mv .../partial/ .../completed/` boundary — independent of Claude's discipline.

## Install

### Add the marketplace

In your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "plan-evaluator-gate": {
      "source": {
        "source": "github",
        "repo": "suresh2824/plan-evaluator-gate"
      }
    }
  },
  "enabledPlugins": {
    "plan-evaluator-gate@plan-evaluator-gate": true
  }
}
```

Then restart your Claude Code session. The skill is auto-discovered.

### Optional: strict-mode hook

For enforcement at the `git mv` boundary (independent of Claude's discipline), add a PreToolUse entry to your `.claude/settings.json`. The hook path depends on your install scope:

**User-scope install** (the default — what `claude plugin install` produces):

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

**Project-scope install:** swap `$HOME` for `$CLAUDE_PROJECT_DIR`.

> **Version pin:** the `0.1.0` segment in the path is the plugin version. After a plugin upgrade, run `claude plugin details plan-evaluator-gate@plan-evaluator-gate` to find the new version segment and update the hook path. (Future improvement: declare the hook in `marketplace.json` so Claude Code auto-wires it without a manual settings.json edit.)

The hook fires only on `git mv .../partial/<plan>.md .../completed/...` patterns; non-matching commands pass through.

**Bypass for intentional exceptions:** `PLAN_EVALUATOR_GATE_BYPASS=1`

## What counts as an Evaluator?

Pick one (or combine):

- **Test command** — `pytest path::test_function`, `npx playwright test specs/<feature>.spec.ts`, `cargo test <name>`, `go test ./pkg/...` — exits 0 on pass
- **HTTP assertion** — `curl -fsS <url>` with expected status + body shape
- **Database query** — a SELECT (or equivalent) asserting expected state
- **Skill invocation** — a project-local `verify-*` skill that returns success
- **Rubric pass-list** — N/N criteria met by manual inspection (for AI-system or design plans)

## Example plan section that PASSES the gate

````markdown
## Evaluator

```bash
pytest tests/auth/test_session_refresh.py::test_token_rotation -v
```

Expected: PASS. Verifies the refresh-token rotation flow returns a new access
token, invalidates the old refresh token, and writes the rotation event to
the audit log.
````

## Relationship to `obra/superpowers`

This plugin **complements** [`obra/superpowers`](https://github.com/obra/superpowers); it does NOT replace `writing-plans`. You should install both.

Upstream PR [obra/superpowers#1627](https://github.com/obra/superpowers/pull/1627) proposes folding the Evaluator section + Self-Review check directly into the `writing-plans` SKILL.md. **If/when that merges, this plugin becomes redundant** — uninstall it and rely on the upstream pattern.

Until then, this plugin lets any Claude Code user adopt the gate without waiting on the upstream review cycle.

## License

[MIT](LICENSE) — same as `obra/superpowers`.
