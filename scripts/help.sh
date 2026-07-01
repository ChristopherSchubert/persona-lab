#!/usr/bin/env bash
# help.sh — what every script does and how to run it
set -euo pipefail

cat <<'EOF'
persona-lab scripts
───────────────────────────────────────────────────────────────

DAILY OPERATIONS
  cycle.sh                    One full SDLC pass: triage-reviews → dispatch → integrate → accept
    --rounds N                Run N passes
    --drain                   Loop until no state:ready issues remain
    --dry-run                 Print what would run, touch nothing
    --repo owner/repo         Override target repo

  dispatch.sh                 Pick the highest-priority ready issue and run its persona
    --dry-run

  audit-sweep.sh              Run discovery personas to find new work and file issues
    <persona-slug>            Sweep just one role
    --dry-run

  triage-reviews.sh           Greg reviews every open PR that hasn't had his pass yet
    --dry-run

  integrate.sh                Merge PRs with gate:eng-had-turn, squash+delete branch
    --dry-run

  accept.sh                   PM acceptance-close of merged issues
    --dry-run

INFORMATION
  rollup.sh                   Summary of run logs (pass/fail counts, personas, outcomes)
  activity.sh                 HTML activity timeline → activity.html
  watchdog.sh                 Detect orphaned locks, stale writers, leaked worktrees

SETUP
  init.sh                     Bootstrap a new repo onto the bus
  setup-labels.sh             Provision GitHub labels (idempotent)
  setup-ruleset.sh            Apply the persona-lock/* branch protection ruleset
  build-agents.sh             Regenerate agents/ from config/

PLUMBING (called by the above — rarely run directly)
  lock.sh                     Claim/release the writer lock
  queue.sh                    Post an enveloped bus record as a GitHub comment
  review.sh                   Post a PR review comment through the W1 envelope
  runlog.sh                   Append/update run records in .claude/persona-lab/runs/
  promote.sh                  Move an issue from state:proposed → state:ready
  dedup.sh                    Skip duplicate issue titles before filing
  assign-names.sh <slug>      Print the human name for a persona slug
  assert-access.sh            Verify persona tool access against capability-map.json
  verify-locks.sh             Audit agent files for correct tools: frontmatter
  validate-run-record.sh      Validate a run record JSON string
  gate.sh                     Apply/check gate labels on a PR

ENVIRONMENT VARIABLES (common overrides)
  PL_REPO                     Short repo name (e.g. persona-lab)
  PL_CLAUDE                   Path to claude binary (default: claude)
  PL_DISPATCH_TIMEOUT         Seconds before a hung claude -p is killed
  PL_DRAIN_MAX_PASSES         Safety cap on --drain loops (default: 20)
  PL_READONLY_CAP             Max concurrent reader dispatches (default: 1)
  PL_WORKTREE_ISOLATION       Set to 1 to run writer dispatch in a git worktree
  NO_COLOR                    Set to disable colored output

EOF
