#!/usr/bin/env bash
# integrate.sh — the INTEGRATE pass (#149): merge PRs whose gate labels are green, then hand off
# to the PM for the acceptance close. This is the CLOSE reactor, counterpart to dispatch.sh (the
# PRODUCE reactor). It runs ONE pass and stops; like dispatch it is meant to be run from a terminal
# (or a scheduler), never nested inside a Claude session, and it can gain --drain later.
#
# GATE SIGNAL (machine-readable labels). The bus runs under a single `gh` identity, which cannot use
# GitHub's native PR approvals on its own PRs (#149/#165) — so the gate reads LABELS applied by the
# reviewers when they post a verdict, not `gh pr review` state:
#   - gate:eng-approved        required on EVERY PR (Lead Engineer approved the code)
#   - gate:qa-approved         required IFF the diff touches tests/ or scripts/ (Priya signed off)
#   - gate:changes-requested   BLOCKS merge (a reviewer asked for changes; clear it on re-approval)
#
# On a green PR the Release Engineer merges it: `--squash --delete-branch`, NEVER `--admin`/force, with
# the pre-merge default-branch SHA checkpointed to the run-log first (revert target). The PR is then
# labelled `state:merged` to hand off to the PM. Per the locked founder decisions (#149): gated-
# autonomous RE merge; no force/self-merge; checkpoint before destructive; and the PM posts the
# acceptance close as a SEPARATE step — so THIS SCRIPT NEVER CLOSES AN ISSUE.
#
# Testability: gh is stubbed in tests (PL_FAKE_PRS / PL_GH_LOG). NO real merge happens in tests/dev.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

dry_run=0; repo_override=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) dry_run=1; shift;;
  --repo)    repo_override="$2"; shift 2;;
  *)         pl_die "integrate: unknown arg $1";;
esac; done

ghrepo="${repo_override:-$(pl_gh_repo)}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"

# A PR requires QA sign-off only when it touches the test/script surface Priya gates.
qa_required() { printf '%s\n' "$1" | grep -qE '^(tests/|scripts/)'; }
has_label()   { printf '%s\n' "$2" | grep -qxF "$1"; }

prs="$(gh pr list --repo "$ghrepo" --state open --json number,labels)"
nums="$(printf '%s' "$prs" | jq -r '.[].number' 2>/dev/null || true)"
[ -n "$nums" ] || { echo "integrate: no open PRs" >&2; exit 0; }

merged=0
for num in $nums; do
  labels="$(printf '%s' "$prs" | jq -r --arg n "$num" '.[] | select(.number==($n|tonumber)) | .labels[].name')"
  files="$(gh pr view "$num" --repo "$ghrepo" --json files | jq -r '.files[].path' 2>/dev/null || true)"

  # FAIL-SAFE (Greg's review): an empty file list means the QA surface is UNKNOWN — a real PR always
  # touches at least one file, so empty means `gh pr view` failed/rate-limited. Never merge blind: a
  # tests/ or scripts/ change could otherwise slip past Priya's required gate. Skip and retry next pass.
  if [ -z "$files" ]; then
    echo "integrate: PR #${num} file listing empty/failed — skipping (can't confirm QA surface)" >&2; continue
  fi

  # Blocked: a reviewer asked for changes.
  if has_label "gate:changes-requested" "$labels"; then
    echo "integrate: PR #${num} blocked (gate:changes-requested) — skipping" >&2; continue
  fi
  # Eng approval is always required.
  if ! has_label "gate:eng-approved" "$labels"; then
    echo "integrate: PR #${num} not eng-approved — skipping" >&2; continue
  fi
  # QA approval required only when the diff touches tests/ or scripts/.
  if qa_required "$files" && ! has_label "gate:qa-approved" "$labels"; then
    echo "integrate: PR #${num} touches tests/ or scripts/ but is not qa-approved — skipping" >&2; continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "integrate (dry-run): would merge PR #${num} (--squash, gated) and label it state:merged for PM close" >&2
    continue
  fi

  # Checkpoint before the destructive step: record the pre-merge default-branch SHA so a bad merge
  # is revertible to a known point (founder decision: checkpoint-before-destructive).
  presha="$(git rev-parse origin/main 2>/dev/null || echo unknown)"
  "$here/runlog.sh" append --persona "release-engineer" --repo "$repo" --trigger "integrate" \
    --outcome "checkpoint" --record-type "integrate" --action "pre-merge origin/main=${presha}" \
    --issue-number "$num" 2>/dev/null || true

  # Gated-autonomous merge: squash + delete branch, NO --admin, NO force. RE is the merger; the
  # eng/qa gate labels prove an INDEPENDENT reviewer approved (the no-self-merge guarantee).
  if gh pr merge "$num" --repo "$ghrepo" --squash --delete-branch </dev/null >/dev/null 2>&1; then
    gh pr edit "$num" --repo "$ghrepo" --add-label "state:merged" </dev/null >/dev/null 2>&1 || true
    "$here/runlog.sh" append --persona "release-engineer" --repo "$repo" --trigger "integrate" \
      --outcome "merged" --record-type "integrate" --action "merge" --issue-number "$num" 2>/dev/null || true
    echo "${PL_C_OK}integrate: merged PR #${num} (squash) -> labelled state:merged, handed to PM for acceptance close${PL_C_RST}" >&2
    merged=$((merged+1))
  else
    echo "${PL_C_ERR}integrate: PR #${num} merge FAILED (left open, gates intact)${PL_C_RST}" >&2
  fi
done

echo "${PL_C_HEAD}integrate: pass complete — ${merged} merged${PL_C_RST}" >&2
exit 0

# ──────────────────────────────────────────────────────────────────────────────────────
# CADENCE (OFF by design): one pass, then stop. Point a scheduler at it for periodic integration,
# or run it after a dispatch drain. The PM acceptance-close step is separate and is NOT done here.
