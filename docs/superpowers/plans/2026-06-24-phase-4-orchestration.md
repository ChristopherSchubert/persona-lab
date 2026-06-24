# Phase 4 — orchestration core Implementation Plan (deterministic core; live enablement deferred)

> superpowers:subagent-driven-development. Builds on Phases 1–3.

**Goal:** Build the deterministic orchestration core — run-log rollups, the watchdog/reaper, and the lock ruleset-setup script — all unit-tested. Defer the outward live enablement (GitHub App bot, cron, applying the ruleset, real `claude -p` auto-mode loops), which are account/repo-level actions the human enables, off by default.

## Task P4A: `scripts/rollup.sh` — deterministic run-log → summary
**Files:** create `scripts/rollup.sh`, `tests/rollup.bats`
- [ ] `rollup.sh [--since <date>] [--cycle <id>]` reads the NDJSON run-log (`$(pl_config_dir)/runs/*.ndjson`, or `$PL_RUNS`) and prints a deterministic summary grouped by persona + outcome (counts of acted/slept/escalated/parked, total cost_tokens). Pure `jq`, no model. TDD: feed fixture NDJSON, assert the aggregation. Commit `feat(rollup): deterministic run-log summary`.

## Task P4B: `scripts/watchdog.sh` — detect orphans/stale locks/wedged funnel
**Files:** create `scripts/watchdog.sh`, `tests/watchdog.bats`
- [ ] `watchdog.sh scan` reports (deterministically): run records with `ts_start` but no terminal `outcome` (orphaned wakes), within a `--grace` window. (Stale-lock + wedged-funnel detection are noted as gh-dependent and stubbed/deferred.) TDD with fixture NDJSON. Output is a report (re-dispatch is the orchestrator's job, noted). Commit `feat(watchdog): orphaned-wake detection`.

## Task P4C: `scripts/setup-ruleset.sh` — build (don't apply) the lock-branch ruleset
**Files:** create `scripts/setup-ruleset.sh`, `tests/setup-ruleset.bats`
- [ ] `setup-ruleset.sh --dry-run` prints the `gh api` ruleset payload that would protect `persona-lock/*` (restrict creation/deletion/non-ff, bypass=bot) WITHOUT applying it. Live apply (no `--dry-run`) is gated behind an explicit confirm + is the human's outward action. TDD asserts the dry-run payload shape (valid JSON, targets persona-lock/*). Commit `feat(ruleset): persona-lock ruleset setup (dry-run; live apply deferred)`.

## Acceptance (P4D, unit)
- [ ] Full suite green; rollup aggregates a fixture; watchdog flags an orphaned wake; setup-ruleset --dry-run emits valid JSON. Commit acceptance note. **Deferred (outward, human-enabled): GitHub App bot, cron/scheduling, live ruleset apply, real claude -p auto-mode loops — all off by default per the autonomy invariant.**

## Out of scope (outward / human-enabled)
- Creating the GitHub App bot; enabling cron / the ~9am scan; applying the ruleset live; auto-mode unattended `claude -p` loops; the live SSE dashboard.
