#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

[ "${1:-}" = "check" ] || pl_die "usage: gate.sh check --head <sha>"; shift

[ "${1:-}" = "--head" ] || pl_die "gate: --head <sha> is required"
head="${2:-}"
[ -n "$head" ] || pl_die "gate: --head requires a non-empty SHA"

cfg="$(pl_repo_root)/.claude/persona-lab"

[ -f "$cfg/verified.marker" ] || pl_die "gate: verification manifest did not run (no marker) — not done"

rj="$cfg/review.json"
[ -f "$rj" ] || pl_die "gate: no REVIEW record"
[ "$(jq -r .verdict "$rj")" = "approved" ] || pl_die "gate: REVIEW not approved"
[ "$(jq -r .commit_sha "$rj")" = "$head" ] || pl_die "gate: REVIEW cites a stale commit (HEAD moved) — re-review"

budget="$cfg/diff_budget.json"
if [ -f "$budget" ]; then
  ml="$(jq -r .max_lines "$budget")"
  mf="$(jq -r .max_files "$budget")"
  # Guard against first-commit case where HEAD~1 doesn't exist.
  # Brace grouping ensures || true absorbs the non-zero git exit before the pipe,
  # so awk/wc receive empty input (→ 0) rather than aborting under set -o pipefail.
  lines="$({ git diff --numstat HEAD~1 2>/dev/null || true; } | awk '{a+=$1+$2} END{print a+0}')"
  files="$({ git diff --name-only HEAD~1 2>/dev/null || true; } | wc -l | tr -d ' ')"
  [ "${lines:-0}" -le "$ml" ] || pl_die "gate: diff $lines lines > budget $ml — re-scope"
  [ "${files:-0}" -le "$mf" ] || pl_die "gate: diff $files files > budget $mf — re-scope"
fi

echo "gate: pass"
