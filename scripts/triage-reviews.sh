#!/usr/bin/env bash
# triage-reviews.sh — the PM review-triage pass (#149/#196): the produce→review TRIGGER.
#
# When a persona opens a PR, nothing yet dispatches its reviewers (dispatch.sh selects state:ready
# issues; a PR-opened issue sits in inert state:in_review). This pass closes that gap WITHOUT moving
# routing off the PM: it dispatches Sarah (the PM) with the open PRs awaiting review; she routes each
# to its gate owner(s) per Remy's RACI (code → Lead Engineer; tests/scripts → +Head of QA; visual →
# +Head of Design). Sarah has no shell, so she RETURNS the review tasks and the harness files them
# routed (persona:<slug> + state:ready + priority) — the normal dispatch cycle then picks them up,
# each reviewer returns a REVIEW verdict (→ review.sh on the PR → gate label), integrate.sh merges,
# accept.sh closes. Routing stays with the PM (CLAUDE.md), not the orchestrator.
#
# Run from a terminal/scheduler, never nested in a Claude session. claude is invoked via
# ${PL_CLAUDE:-claude} (stubbed in tests); NO real model call or issue is created in tests/dev.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

CLAUDE_BIN="${PL_CLAUDE:-claude}"
dry_run=0; repo_override=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) dry_run=1; shift;;
  --repo)    repo_override="$2"; shift 2;;
  *)         pl_die "triage-reviews: unknown arg $1";;
esac; done

ghrepo="${repo_override:-$(pl_gh_repo)}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"

# The fixed review-gate owners (CLAUDE.md): code → Greg, QA → Priya, visual → Laura. The PM routes
# WITHIN this set; the harness refuses any slug outside it (a review task can't name a non-gate owner).
_is_gate_reviewer() { case "$1" in lead-engineer|head-of-qa|head-of-design) return 0;; *) return 1;; esac; }

# Open PRs still awaiting review: not yet eng-approved, not already merged/accepted.
prs_json="$(gh pr list --repo "$ghrepo" --state open --json number,title,labels,files)"
pending="$(printf '%s' "$prs_json" | jq -c '
  [ .[]
    | ([.labels[].name]) as $l
    | select(($l|index("gate:eng-approved"))==null and ($l|index("state:merged"))==null and ($l|index("state:accepted"))==null)
    | {number, title, files: [.files[].path]} ]')"
count="$(printf '%s' "$pending" | jq 'length' 2>/dev/null || echo 0)"
if [ "$count" -eq 0 ]; then echo "triage-reviews: no PRs awaiting review" >&2; exit 0; fi

# Dispatch the PM (Sarah) to route the pending PRs. She returns the review tasks; the harness files them.
agent="agents/product-manager.md"
[ -f "$agent" ] || pl_die "triage-reviews: missing $agent"
allowed="$(awk -F': ' '/^tools:/{gsub(/, */," ",$2); print $2; exit}' "$agent")"
name="$("$here/assign-names.sh" product-manager 2>/dev/null || echo "Sarah")"
role="$(awk -F' — ' '/^# /{t=$1; sub(/^# +/,"",t); print t; exit}' "$agent")"; [ -n "$role" ] || role="Product Manager"

existing="$(gh issue list --repo "$ghrepo" --state open --json title --limit 300 | jq -r '.[].title' 2>/dev/null || true)"

prompt="$(printf 'You are the PM triaging open pull requests into REVIEW tasks, routing each to its gate owner(s) per the RACI:\n- EVERY PR needs the Lead Engineer (reviewer slug: lead-engineer).\n- A PR that changes tests/ or scripts/ ALSO needs Head of QA (head-of-qa).\n- A PR with visual/UI changes ALSO needs Head of Design (head-of-design).\n\nOpen PRs awaiting review (number, title, files):\n%s\n\nReview tasks ALREADY open — do NOT duplicate (match on title):\n%s\n\nYou CANNOT file issues — return ONLY the FINAL ```json fenced array, nothing after the closing fence. One item per (PR, reviewer):\n```json\n[{"pr":<number>,"reviewer":"<lead-engineer|head-of-qa|head-of-design>","priority":"<p0|p1|p2|p3>","title":"Review PR #<number> — <Role>","body":"<what this gate should check, as markdown>"}]\n```\n' "$pending" "${existing:-(none)}")"

echo "triage-reviews: -> PM (${name}) routing ${count} PR(s) awaiting review" >&2
raw="$("$CLAUDE_BIN" -p "$prompt" --append-system-prompt-file "$agent" --allowedTools $allowed --output-format json 2>/dev/null || true)"
result="$(printf '%s' "$raw" | jq -r '.result // empty' 2>/dev/null || true)"
[ -n "$result" ] || result="$raw"
arr="$(printf '%s' "$result" | pl_extract_json 2>/dev/null || true)"
if ! printf '%s' "$arr" | jq -e 'type=="array"' >/dev/null 2>&1; then
  echo "triage-reviews: PM returned no parseable review-task array — nothing filed" >&2; exit 0
fi

n="$(printf '%s' "$arr" | jq 'length')"; filed=0; dup=0
for ((i=0; i<n; i++)); do
  pr="$(printf '%s'    "$arr" | jq -r ".[$i].pr // empty")"
  reviewer="$(printf '%s' "$arr" | jq -r ".[$i].reviewer // empty")"
  prio="$(printf '%s'  "$arr" | jq -r ".[$i].priority // \"p2\"")"
  title="$(printf '%s' "$arr" | jq -r ".[$i].title // empty")"
  body="$(printf '%s'  "$arr" | jq -r ".[$i].body // empty")"
  [ -n "$pr" ] && [ -n "$reviewer" ] && [ -n "$title" ] && [ -n "$body" ] || continue
  if ! _is_gate_reviewer "$reviewer"; then
    echo "triage-reviews: rejected non-gate reviewer '${reviewer}' for PR #${pr}" >&2; continue
  fi
  if printf '%s\n' "$existing" | grep -qxF "$title"; then dup=$((dup+1)); continue; fi
  case "$prio" in p0|p1|p2|p3) ;; *) prio="p2";; esac

  if [ "$dry_run" -eq 1 ]; then
    echo "triage-reviews (dry-run): would file '${title}' routed persona:${reviewer} state:ready ${prio}" >&2
    continue
  fi

  if url="$("$here/queue.sh" file --persona "$name" --tier "$role" --type ROUTING --title "$title" --body "$body" --repo "$ghrepo" 2>&1)"; then
    num="${url##*/}"
    "$here/queue.sh" label "$num" --add "persona:${reviewer}" --repo "$ghrepo" >/dev/null 2>&1 || true
    "$here/queue.sh" label "$num" --add "state:ready"         --repo "$ghrepo" >/dev/null 2>&1 || true
    "$here/queue.sh" label "$num" --add "priority:${prio}"    --repo "$ghrepo" >/dev/null 2>&1 || true
    existing="$(printf '%s\n%s' "$existing" "$title")"
    filed=$((filed+1))
    echo "triage-reviews: filed #${num} '${title}' → persona:${reviewer} state:ready ${prio}" >&2
  else
    echo "triage-reviews: FILE FAILED for '${title}':" >&2; printf '%s\n' "$url" | sed 's/^/    /' >&2
  fi
done

"$here/runlog.sh" append --persona "product-manager" --repo "$repo" --trigger "triage-reviews" \
  --outcome "triaged" --record-type "triage" --action "route-reviews" 2>/dev/null || true
echo "triage-reviews: pass complete — ${filed} review task(s) filed, ${dup} duplicate(s) skipped" >&2
exit 0
