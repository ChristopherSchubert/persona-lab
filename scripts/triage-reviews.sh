#!/usr/bin/env bash
# triage-reviews.sh — the REVIEW pass (#215). Dispatch the gate reviewer(s) DIRECTLY against each open
# PR that still needs review and post their verdict as a COMMENT + gate label ON THE PR. It NEVER
# creates a "Review PR #N" tracking issue — reviews live on the PR (bus-hygiene, #196). Mirrors
# audit-sweep: dispatch persona → get verdict JSON → harness posts it (the persona has no shell).
#
# Gate reviewers (the fixed code/QA gate, CLAUDE.md): Lead Engineer on EVERY PR; + Head of QA when the
# diff touches tests/ or scripts/. Each (PR, reviewer) is reviewed at most once — deduped on the gate
# label already being present. A PR carrying gate:changes-requested is skipped (awaiting the dev's fix).
#
# Run from a terminal/scheduler, never nested. claude is invoked via ${PL_CLAUDE:-claude} (stubbed in
# tests); NO real model call, PR comment, or issue is made in tests/dev.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

CLAUDE_BIN="${PL_CLAUDE:-claude}"
dry_run=0; repo_override=""
while [ $# -gt 0 ]; do case "$1" in
  --help|-h)  cat <<'HELP'
Usage: scripts/triage-reviews.sh [--dry-run] [--repo owner/repo]

  --dry-run    Print which PRs would be reviewed, invoke nothing
  --repo       Override target repo

Greg reviews every open PR that hasn't had gate:eng-had-turn set yet.
One review per PR — findings go in a comment, then the PR merges next integrate pass.
HELP
              exit 0;;
  --dry-run) dry_run=1; shift;;
  --repo)    repo_override="$2"; shift 2;;
  *)         pl_die "triage-reviews: unknown arg $1";;
esac; done

ghrepo="${repo_override:-$(pl_gh_repo)}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"

# Fixed gate: Lead Engineer always; Head of QA when the diff touches tests/ or scripts/.
_gate_reviewers() {
  echo "lead-engineer"
}
_gate_label_for() { case "$1" in lead-engineer) echo "gate:eng-approved";; *) echo "";; esac; }
has_label() { printf '%s\n' "$2" | grep -qxF "$1"; }

# Dispatch ONE gate reviewer against a PR and post the verdict ON THE PR (comment + gate label). No issue.
review_one() {
  local pr="$1" slug="$2" diff="$3" agent="agents/$2.md"
  [ -f "$agent" ] || { echo "triage-reviews: no agent file $agent — skipping ${slug}" >&2; return 0; }
  local allowed name role glabel model model_args
  allowed="$(awk -F': ' '/^tools:/{gsub(/, */," ",$2); print $2; exit}' "$agent")"
  name="$("$here/assign-names.sh" "$slug" 2>/dev/null || echo "$slug")"
  role="$(awk -F' — ' '/^# /{t=$1; sub(/^# +/,"",t); print t; exit}' "$agent")"; [ -n "$role" ] || role="$slug"
  glabel="$(_gate_label_for "$slug")"
  model="$(pl_agent_model "$agent")"
  model_args="${model:+--model $model}"

  local prompt
  prompt="$(printf 'You are reviewing pull request #%s on repo %s as the gate reviewer for your role. The diff follows. Do a real review — find what is wrong; do not rubber-stamp.\n\n----- PR #%s DIFF -----\n%s\n----- END DIFF -----\n\nYou do NOT post anything — the harness posts your verdict as a PR comment and sets the gate label from it. End your turn by emitting ONLY this FINAL ```json fenced block, nothing after it:\n```json\n{"record_type":"REVIEW","pr":%s,"verdict":"<approve|request-changes|comment>","body":"<your review as markdown, citing specifics>"}\n```\n' "$pr" "$repo" "$pr" "$diff" "$pr")"

  echo "${PL_C_HEAD}triage-reviews: -> ${name} (${role}) reviewing PR #${pr}${PL_C_RST}" >&2
  if [ "$dry_run" -eq 1 ]; then
    echo "triage-reviews (dry-run): would review PR #${pr} as ${slug} and post comment + gate label on the PR" >&2
    return 0
  fi

  local raw result rec verdict body
  # stream-json so ALL assistant turns are available — --output-format json only gives the LAST
  # turn; a reviewer who uses tools and emits the JSON in an earlier turn is silently lost.
  raw="$("$CLAUDE_BIN" -p "$prompt" --append-system-prompt-file "$agent" $model_args --allowedTools $allowed --output-format stream-json --verbose 2>/dev/null || true)"
  # Concatenate the text from every assistant message turn (not just the final result event).
  result="$(printf '%s' "$raw" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null || true)"
  [ -n "$result" ] || result="$(printf '%s' "$raw" | jq -r '.result // empty' 2>/dev/null || true)"
  rec="$(printf '%s' "$result" | pl_extract_json 2>/dev/null || true)"
  verdict="$(printf '%s' "$rec" | jq -r '.verdict // empty' 2>/dev/null || true)"
  body="$(printf '%s'    "$rec" | jq -r '.body // empty'    2>/dev/null || true)"
  if [ -z "$body" ]; then
    echo "${PL_C_WARN}triage-reviews: <- ${name} returned no parseable review for PR #${pr} — skipping (no comment, no label)${PL_C_RST}" >&2
    return 0
  fi

  # Post the verdict as a PR COMMENT (#216: never native --approve on own PR) and mark Greg's turn done.
  # One review per PR — Greg posts findings, sets gate:eng-had-turn, then the PR merges.
  # If he has blocking concerns he opens new issues; he does not re-review.
  "$here/review.sh" "$pr" --persona "$name" --tier "$role" --type REVIEW --body "$body" --event comment --repo "$ghrepo" </dev/null >/dev/null 2>&1 || true
  gh pr edit "$pr" --repo "$ghrepo" --add-label "gate:eng-had-turn" --remove-label "gate:changes-requested" </dev/null >/dev/null 2>&1 || true
  case "$verdict" in
    approve|approved)
      gh pr edit "$pr" --repo "$ghrepo" --add-label "$glabel" </dev/null >/dev/null 2>&1 || true
      echo "${PL_C_OK}triage-reviews: <- ${name} approved PR #${pr} → ${glabel}${PL_C_RST}" >&2 ;;
    request-changes|request_changes|changes-requested)
      echo "${PL_C_WARN}triage-reviews: <- ${name} noted concerns on PR #${pr} → gate:eng-had-turn (concerns go to new issues, not a block)${PL_C_RST}" >&2 ;;
    *)
      echo "${PL_C_DIM}triage-reviews: <- ${name} commented on PR #${pr} → gate:eng-had-turn${PL_C_RST}" >&2 ;;
  esac
}

prs="$(gh pr list --repo "$ghrepo" --state open --json number,labels)"
nums="$(printf '%s' "$prs" | jq -r '.[].number' 2>/dev/null || true)"
[ -n "$nums" ] || { echo "triage-reviews: no open PRs" >&2; exit 0; }

reviewed=0
for pr in $nums; do
  labels="$(printf '%s' "$prs" | jq -r --arg n "$pr" '.[] | select(.number==($n|tonumber)) | .labels[].name')"
  has_label "state:merged"   "$labels" && continue
  has_label "state:accepted" "$labels" && continue
  # Skip if Greg already had his one turn
  if has_label "gate:eng-had-turn" "$labels"; then
    echo "triage-reviews: PR #${pr} already reviewed — skipping" >&2; continue
  fi

  files="$(gh pr view "$pr" --repo "$ghrepo" --json files | jq -r '.files[].path' 2>/dev/null || true)"
  diff="$(gh pr diff "$pr" --repo "$ghrepo" 2>/dev/null | head -c 60000 || true)"

  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    review_one "$pr" "$slug" "$diff" && reviewed=$((reviewed+1)) || true
  done < <(_gate_reviewers "$files")
done

"$here/runlog.sh" append --persona "product-manager" --repo "$repo" --trigger "triage-reviews" \
  --outcome "reviewed" --record-type "triage" --action "review-prs" 2>/dev/null || true
echo "${PL_C_HEAD}triage-reviews: pass complete — ${reviewed} review(s) dispatched (posted on the PRs, no issues)${PL_C_RST}" >&2
exit 0
