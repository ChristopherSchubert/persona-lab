#!/usr/bin/env bash
# dispatch.sh — ONE dispatch cycle (issue #45, "personas operate the bus").
#
# Founder-approved autonomy model: ONE issue per cycle. A sweep dispatches the SINGLE
# highest-ready dispatchable issue, captures the outcome, and STOPS. No chaining.
# The schedule itself stays OFF — nothing here installs cron/launchd/hooks. To enable a
# recurring sweep, wire an external scheduler to run this script (see the note at the
# bottom of this file and the README).
#
# Dispatchable = open issue that is READY and has an assigned persona:
#   - ready signal:   carries `state:ready` (ADR-0001 `ready` state) ...
#   - persona signal: carries exactly one `persona:<slug>` label (this file defines the
#                     convention; <slug> is an agents/<slug>.md persona)
#   - not blocked:    no `blocked-by:*`, `needs-human:*`, or `quarantine` label
# Highest = lowest priority number (priority:p0 > p1 > p2 > p3; default p3), ties broken
# by oldest issue number.
#
# An issue that is ready+unblocked but carries no `persona:` label is SKIPPED (and the
# reason logged) — dispatch never guesses an owner.
#
# Testability: the model is invoked via ${PL_CLAUDE:-claude}; tests stub it. NO real
# `claude` call happens in tests/dev. lock.sh is reachable via ${PL_LOCK_SH} for stubbing.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

dry_run=0
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) dry_run=1; shift;;
  *) pl_die "dispatch: unknown arg $1";;
esac; done

CLAUDE_BIN="${PL_CLAUDE:-claude}"
LOCK_SH="${PL_LOCK_SH:-$here/lock.sh}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"

# Writer personas hold the writer lock before dispatch. Per manifest engagement and
# persona.md §3, the Developer is the sole `writes`-capacity persona. Resolving capacity
# from the manifest needs yq for nested keys (pl_manifest_get fails closed on those), so
# the writer set is named here explicitly; extend this list if another writer is added.
is_writer_persona() { case "$1" in developer) return 0;; *) return 1;; esac; }

# ── Select the single highest-ready dispatchable issue ────────────────────────────────
# Pull open issues with number + labels, then rank in jq:
#   keep:  has state:ready AND a persona:* label AND no blocking label
#   sort:  priority asc (p0=0 … p3=3, default 3), then number asc
#   take:  the first one. Emit "<number>\t<persona-slug>" or nothing.
issues_json="$(gh issue list --state open --json number,labels --limit 200)"

selected="$(printf '%s' "$issues_json" | jq -r '
  def labelset: [.labels[].name];
  def prio:
    (labelset | map(select(startswith("priority:p"))) | .[0] // "priority:p3"
     | ltrimstr("priority:p") | tonumber? // 3);
  def persona:
    (labelset | map(select(startswith("persona:"))) | .[0] // "" | ltrimstr("persona:"));
  def blocked:
    (labelset | any(.[]; startswith("blocked-by:") or startswith("needs-human:") or . == "quarantine"));
  [ .[]
    | select(labelset | any(.[]; . == "state:ready"))
    | select(blocked | not)
    | select(persona != "")
    | {number, persona: persona, prio: prio}
  ]
  | sort_by(.prio, .number)
  | .[0]
  | if . == null then "" else "\(.number)\t\(.persona)" end
')"

# Distinguish "nothing dispatchable" from "ready but persona-less" for the skip log.
if [ -z "$selected" ]; then
  # Were there ready+unblocked issues that we skipped only for lacking a persona label?
  skipped="$(printf '%s' "$issues_json" | jq -r '
    def labelset: [.labels[].name];
    def blocked:
      (labelset | any(.[]; startswith("blocked-by:") or startswith("needs-human:") or . == "quarantine"));
    [ .[]
      | select(labelset | any(.[]; . == "state:ready"))
      | select(blocked | not)
      | select(labelset | any(.[]; startswith("persona:")) | not)
      | .number ] | join(" ")')"
  if [ -n "$skipped" ]; then
    echo "dispatch: skipping ready issue(s) with no persona: label (no owner to dispatch): $skipped" >&2
  fi
  echo "dispatch: nothing ready to dispatch" >&2
  exit 0
fi

issue_number="${selected%%$'\t'*}"
persona="${selected#*$'\t'}"
agent="agents/${persona}.md"

if [ "$dry_run" -eq 1 ]; then
  echo "dispatch (dry-run): would dispatch issue #${issue_number} to persona '${persona}' via ${CLAUDE_BIN} -p ${agent}"
  exit 0
fi

# ── Writer lock around the dispatch (writer personas only) ────────────────────────────
locked=0
if is_writer_persona "$persona"; then
  "$LOCK_SH" claim --repo "$repo" --holder "$persona" >/dev/null
  locked=1
fi
# Always release the lock on exit, even on failure of the dispatch itself.
release_lock() { [ "$locked" -eq 1 ] && "$LOCK_SH" release --repo "$repo" >/dev/null 2>&1 || true; }
trap release_lock EXIT

# ── Dispatch one unit of work, capture the outcome ────────────────────────────────────
prompt="Operate issue #${issue_number} on repo ${repo}. One bounded unit of work per ADR-0001; \
post all bus writes via scripts/queue.sh and any PR review via scripts/review.sh."
outcome="dispatched"
if "$CLAUDE_BIN" -p "$agent" "$prompt"; then
  outcome="dispatched"
else
  outcome="failed"
fi

# ── Real run record for this dispatch ─────────────────────────────────────────────────
"$here/runlog.sh" append \
  --persona "$persona" \
  --repo    "$repo" \
  --trigger "dispatch" \
  --outcome "$outcome" \
  --record-type "dispatch" \
  --action  "dispatch" \
  --issue-number "$issue_number" || true   # non-fatal: don't lose the dispatch over logging

exit 0

# ──────────────────────────────────────────────────────────────────────────────────────
# ENABLING THE SCHEDULE (left OFF by design):
#   This script runs exactly one cycle and stops. To run it on a cadence, point an
#   external scheduler at it — nothing is installed automatically. Examples:
#     cron:     */15 * * * * cd /path/to/persona-lab && scripts/dispatch.sh >> dispatch.log 2>&1
#     launchd:  a StartCalendarInterval/StartInterval job calling scripts/dispatch.sh
#   Keep PL_CLAUDE unset in production so the real `claude` binary is used; set it to a
#   stub in tests/dev so no paid-API call is made.
