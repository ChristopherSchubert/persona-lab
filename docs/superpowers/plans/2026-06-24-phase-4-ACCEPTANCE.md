# Phase 4 — acceptance evidence (orchestration core, deterministic)

Run 2026-06-24. Full suite: **56/56 bats green**.

- `rollup.sh` — deterministic run-log summary: per-persona × outcome counts + total cost_tokens (no model).
- `watchdog.sh scan --grace-min N` — flags stale `pending` wakes (orphaned/crashed) past the grace window; terminal/recent records not flagged. (Stale-lock + wedged-funnel detection noted as gh-dependent, deferred.)
- `setup-ruleset.sh --dry-run` — emits a valid GitHub ruleset payload protecting `persona-lock/**` (deletion/non-ff/update restricted); `--apply` is safely deferred (no live POST until the persona-system App id exists).

**Deferred (outward / human-enabled, off by default per the autonomy invariant):** the GitHub App bot, cron / the ~9am scan, live ruleset apply, real `claude -p` auto-mode loops, the live SSE dashboard. These are account/repo-level actions the human enables when ready.
