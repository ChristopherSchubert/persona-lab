#!/usr/bin/env bash
# watchdog.sh — orphaned-state detection + recovery
#
# Usage:
#   watchdog.sh scan          [--grace-min N]   # stale pending wakes (run-log)
#   watchdog.sh reclaim-locks [--grace-min N]   # orphaned writer locks (issue #8)
#
# scan: scans run-log NDJSON for outcome=="pending" records older than N minutes
#   (default 30). A stale pending indicates an orchestrator crash that left a wake
#   without a terminal outcome.
#
# reclaim-locks: an interrupted Developer (hard kill before the EXIT trap fires)
#   leaves an orphaned persona-lock/<repo> ref that blocks every further write.
#   For each lock older than the grace window the watchdog runs the safe recovery:
#     assess (inspect)  → checkpoint (archive the lock commit, no force)
#       → file an incident issue  → reclaim (delete + recreate) → release (unblock).
#   Staleness is decided here (policy); the ref ops live in lock.sh (mechanism).
#   No --force / PATCH anywhere — every ref op is a create-only CAS or a delete.
#
# Date comparison: ISO-8601 ts strings sort lexically (YYYY-MM-DDTHH:MM:SSZ), so we
# compute a threshold string and compare with string inequality. Portable "now minus
# N minutes": try BSD `date -v-${N}M`, fall back to GNU `date -d "${N} minutes ago"`.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

LOCK_SH="${PL_LOCK_SH:-$here/lock.sh}"

# ── arg parsing ──────────────────────────────────────────────────────────────
subcmd="${1:-}"; shift || true
case "$subcmd" in scan|reclaim-locks) ;; *) pl_die "usage: watchdog.sh <scan|reclaim-locks> [--grace-min N]";; esac

grace_min=30
while [ $# -gt 0 ]; do case "$1" in
  --grace-min) grace_min="$2"; shift 2;;
  *) pl_die "unknown arg: $1";;
esac; done

# ── compute threshold (portable: BSD then GNU) ────────────────────────────────
threshold="$(date -u -v-"${grace_min}M" +%FT%TZ 2>/dev/null \
  || date -u -d "${grace_min} minutes ago" +%FT%TZ)"

# ── scan: stale pending wakes ─────────────────────────────────────────────────
if [ "$subcmd" = "scan" ]; then
  runs="$(pl_runs_dir)"
  files=()
  if [ -d "$runs" ]; then
    while IFS= read -r -d '' f; do files+=("$f"); done \
      < <(find "$runs" -maxdepth 1 -name '*.ndjson' -print0 2>/dev/null | sort -z)
  fi

  if [ "${#files[@]}" -eq 0 ]; then
    printf 'watchdog: no run records found\n'; exit 0
  fi

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
  exit 0
fi

# ── reclaim-locks: orphaned writer-lock recovery (issue #8) ───────────────────
locks="$("$LOCK_SH" list 2>/dev/null || true)"
if [ -z "$locks" ]; then
  printf 'watchdog: no writer locks present\n'; exit 0
fi

gh_repo="$(pl_gh_repo)"
any=0
while IFS=$'\t' read -r lrepo lfence; do
  [ -n "$lrepo" ] || continue
  info="$("$LOCK_SH" inspect --repo "$lrepo" 2>/dev/null || echo '{}')"
  claimed_at="$(printf '%s' "$info" | jq -r '.claimed_at // ""')"
  holder="$(printf '%s' "$info" | jq -r '.holder // "?"')"
  [ -n "$claimed_at" ] || continue
  # not stale: a live dispatch still holds it within the grace window — leave it alone.
  [[ "$claimed_at" < "$threshold" ]] || continue

  any=1
  # 1) checkpoint — preserve the orphaned lock commit before touching the ref.
  archive="$("$LOCK_SH" checkpoint --repo "$lrepo")"
  # 2) file an incident issue so a human/PM sees the interrupted dispatch.
  body="$(printf 'An interrupted Developer left an orphaned writer lock; the watchdog reclaimed it.\n\n- repo: `%s`\n- previous holder: `%s`\n- claimed_at: `%s` (older than the %s-min grace window)\n- orphaned fence: `%s`\n- preserved at: `%s`\n\nRecovery: assess → checkpoint → file issue → reclaim (delete + recreate, no force) → release. The writer lock is now free; investigate whether the interrupted issue needs re-dispatch.' \
    "$lrepo" "$holder" "$claimed_at" "$grace_min" "$lfence" "$archive")"
  issue_url="$(gh issue create ${gh_repo:+--repo "$gh_repo"} \
    --title "incident: stale writer-lock reclaimed — $lrepo (was $holder)" \
    --body "$body" 2>/dev/null || echo "(issue create failed)")"
  # 3) reclaim (delete + recreate) then release so every further write is unblocked.
  "$LOCK_SH" reclaim --repo "$lrepo" --holder "watchdog-recovery" >/dev/null 2>&1 || true
  "$LOCK_SH" release --repo "$lrepo" >/dev/null 2>&1 || true

  printf 'RECLAIMED repo=%s holder=%s claimed_at=%s archive=%s issue=%s\n' \
    "$lrepo" "$holder" "$claimed_at" "$archive" "$issue_url"
done <<< "$locks"

[ "$any" -eq 1 ] || printf 'watchdog: no stale locks found (grace=%s min)\n' "$grace_min"
exit 0
