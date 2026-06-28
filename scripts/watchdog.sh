#!/usr/bin/env bash
# watchdog.sh — orphaned-wake (stale pending) detection
#
# Usage: watchdog.sh scan [--grace-min N]
#
# Scans all run-log NDJSON files for records with outcome=="pending" whose
# ts is older than N minutes (default 30). Stale pending records indicate an
# orchestrator crash that left a wake without a terminal outcome.
#
# DEFERRED (require live gh calls — not implemented here):
#   - Stale-lock detection: check for lock files with no active gh run
#   - Wedged-funnel detection: check for queued items with no active dispatch
#
# Date comparison: ISO-8601 ts strings sort lexically (YYYY-MM-DDTHH:MM:SSZ),
# so we compute a threshold timestamp string and compare with string inequality.
# Portable "now minus N minutes": try BSD `date -v-${N}M`, fall back to GNU
# `date -d "${N} minutes ago"`.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

# ── arg parsing ──────────────────────────────────────────────────────────────
subcmd="${1:-}"; shift || true
[ "$subcmd" = "scan" ] || pl_die "usage: watchdog.sh scan [--grace-min N]"

grace_min=30
while [ $# -gt 0 ]; do case "$1" in
  --grace-min) grace_min="$2"; shift 2;;
  *) pl_die "unknown arg: $1";;
esac; done

# ── compute threshold (portable: BSD then GNU) ────────────────────────────────
threshold="$(date -u -v-"${grace_min}M" +%FT%TZ 2>/dev/null \
  || date -u -d "${grace_min} minutes ago" +%FT%TZ)"

# ── collect ndjson files ──────────────────────────────────────────────────────
runs="$(pl_runs_dir)"
files=()
if [ -d "$runs" ]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$runs" -maxdepth 1 -name '*.ndjson' -print0 2>/dev/null | sort -z)
fi

if [ "${#files[@]}" -eq 0 ]; then
  printf 'watchdog: no run records found\n'
  exit 0
fi

# ── find stale pending records ────────────────────────────────────────────────
# A record is stale if: outcome=="pending" AND ts < threshold (lexical compare)
stale="$(cat "${files[@]}" 2>/dev/null \
  | jq -r --arg thresh "$threshold" '
      select(.outcome == "pending" and .ts < $thresh)
      | "STALE_PENDING persona=\(.persona) repo=\(.repo) trigger=\(.trigger) ts=\(.ts)"
    ')"

if [ -z "$stale" ]; then
  printf 'watchdog: no stale pending wakes found (grace=%s min)\n' "$grace_min"
else
  printf 'watchdog: stale pending wakes detected (grace=%s min)\n' "$grace_min"
  printf '%s\n' "$stale"
fi
