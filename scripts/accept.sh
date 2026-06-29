#!/usr/bin/env bash
# accept.sh — the PM ACCEPTANCE-CLOSE step (#149/#196). Counterpart to integrate.sh: integrate MERGES
# (the RE), accept CLOSES (the PM) — two DISTINCT steps per the locked founder decision on #149.
#
# For each merged PR labelled `state:merged` that names its issue with a `Resolves-Issue: #N` trailer,
# the PM (Sarah) posts an enveloped ACCEPTANCE record citing the merge proof, and ONLY if that record
# lands does the issue get closed — never a bare close (ADR-0001: no self-close; acceptance cites
# proof). The PR is then relabelled `state:accepted` so it is not reprocessed on the next pass.
#
# Like dispatch.sh/integrate.sh, this runs from a terminal (or scheduler), never nested in a Claude
# session. gh is stubbed in tests (PL_FAKE_PRS / PL_GH_LOG); NO real close happens in tests/dev.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

dry_run=0; repo_override=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) dry_run=1; shift;;
  --repo)    repo_override="$2"; shift 2;;
  *)         pl_die "accept: unknown arg $1";;
esac; done

ghrepo="${repo_override:-$(pl_gh_repo)}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"
name="$("$here/assign-names.sh" product-manager 2>/dev/null || echo "Sarah")"  # PM display name for the envelope

prs="$(gh pr list --repo "$ghrepo" --state merged --label "state:merged" --json number,body)"
nums="$(printf '%s' "$prs" | jq -r '.[].number' 2>/dev/null || true)"
[ -n "$nums" ] || { echo "accept: nothing awaiting acceptance" >&2; exit 0; }

accepted=0
for pr in $nums; do
  body="$(printf '%s' "$prs" | jq -r --arg n "$pr" '.[] | select(.number==($n|tonumber)) | .body')"
  # The PR must name the issue it resolves with a `Resolves-Issue: #N` trailer (a deliberate marker,
  # NOT a GitHub auto-close keyword — auto-close would bypass PM acceptance). No marker → don't close.
  issue="$(printf '%s' "$body" | grep -oiE 'Resolves-Issue:[[:space:]]*#?[0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
  if [ -z "$issue" ]; then
    echo "accept: PR #${pr} has no 'Resolves-Issue: #N' trailer — skipping (won't close blind)" >&2; continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "accept (dry-run): would post PM acceptance on #${issue} and close it (merged via PR #${pr})" >&2
    continue
  fi

  acc_body="$(printf 'Accepted. PR #%s merged to `main` through the gated pipeline (independent Lead Engineer + QA approval — see the PR reviews). Closing per ADR-0001: PM acceptance, citing the merge as proof, no self-close.' "$pr")"
  # PROOF FIRST: post the enveloped acceptance record. Only if it lands do we close the issue.
  if "$here/queue.sh" comment "$issue" --persona "$name" --tier "Product Manager" --type ASSESSMENT --body "$acc_body" --repo "$ghrepo" >/dev/null 2>&1; then
    gh issue close "$issue" --repo "$ghrepo" --reason completed >/dev/null 2>&1 || true
    gh pr edit "$pr" --repo "$ghrepo" --add-label "state:accepted"    >/dev/null 2>&1 || true
    gh pr edit "$pr" --repo "$ghrepo" --remove-label "state:merged"   >/dev/null 2>&1 || true
    "$here/runlog.sh" append --persona "product-manager" --repo "$repo" --trigger "accept" \
      --outcome "accepted" --record-type "accept" --action "close" --issue-number "$issue" 2>/dev/null || true
    echo "accept: #${issue} accepted & closed (PR #${pr}) → state:accepted" >&2
    accepted=$((accepted+1))
  else
    echo "accept: PR #${pr} → #${issue} acceptance post FAILED — NOT closing (proof-first, ADR-0001)" >&2
  fi
done

echo "accept: pass complete — ${accepted} accepted" >&2
exit 0
