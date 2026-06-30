#!/usr/bin/env bash
# review.sh — post a persona PR review/comment through the W1 envelope.
# Fixes "no envelope on PRs": every PR review or comment a persona makes goes through
# the SAME pl_envelope used for issue comments (img + name + badge, then `AI` · role).
#
# Usage:
#   review.sh <pr#> --persona P --tier "T · Role" --type TYPE --body "…" \
#             [--event approve|comment|request-changes] [--repo o/r]
#
# With --event the review is posted via `gh pr review` (approve/comment/request-changes).
# Without --event it posts a plain enveloped `gh pr comment` (a review note, no verdict).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

pr="${1:?usage: review.sh <pr#> --persona P --tier T --type TYPE --body B [--event approve|comment|request-changes] [--repo o/r]}"
shift

persona="" tier="" rtype="REVIEW" body="" event="" repoflag=()
while [ $# -gt 0 ]; do case "$1" in
  --persona) persona="$2"; shift 2;;
  --tier)    tier="$2";    shift 2;;
  --type)    rtype="$2";   shift 2;;
  --body)    body="$2";    shift 2;;
  --event)   event="$2";   shift 2;;
  --repo)    repoflag=(--repo "$2"); shift 2;;
  *) pl_die "review: unknown arg $1";;
esac; done

[ -n "$persona" ] || pl_die "review: --persona is required"
[ -n "$body" ]    || pl_die "review: --body is required"

enveloped="$(pl_envelope "$persona" "$tier" "$rtype" "$body")"

if [ -n "$event" ]; then
  # Map the friendly event name to the gh pr review verdict flag.
  case "$event" in
    approve)         eventflag="--approve" ;;
    comment)         eventflag="--comment" ;;
    request-changes) eventflag="--request-changes" ;;
    *) pl_die "review: invalid --event '$event' (must be approve|comment|request-changes)";;
  esac
  url="$(gh pr review ${repoflag[@]+"${repoflag[@]}"} "$pr" "$eventflag" --body "$enveloped" </dev/null)"
else
  url="$(gh pr comment ${repoflag[@]+"${repoflag[@]}"} "$pr" --body "$enveloped" </dev/null)"
fi
printf '%s\n' "$url"

# Real run record: the persona's PR action lands on the bus like any other.
repo="$(pl_manifest_get repo 2>/dev/null || echo "")"
"$here/runlog.sh" append \
  --persona "$persona" \
  --repo    "${repo:-unknown}" \
  --trigger "bus" \
  --outcome "posted" \
  --record-type "bus" \
  --action  "bus:review" \
  --issue-number "$pr" \
  ${url:+--artifact-url "$url"} || true   # non-fatal: don't break the PR op
