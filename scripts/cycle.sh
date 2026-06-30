#!/usr/bin/env bash
# cycle.sh — the CONDUCTOR: one full SDLC pass over the bus, so you run ONE command, not six.
# It chains the reactors in dependency order:
#
#   triage-reviews  → PM routes open PRs into review tasks   (produce→review trigger)
#   dispatch        → work one mutator + N readers           (dev work + reviews → verdicts auto-label)
#   integrate       → merge PRs whose gates are green         (checkpointed)
#   accept          → PM acceptance-close of merged work      (proof-first)
#
# Each stage is best-effort: a transient failure in one is logged but does NOT abort the pass, so a
# single pass always advances every other stage. Run it from a terminal or a scheduler (e.g. every few
# hours). Each stage is a real reactor invoked via ${PL_*_SH:-$here/<stage>.sh}, overridable for tests.
#
# --drain (loop to quiescence — the once-a-day backlog cleaner, #187) is intentionally REFUSED until
# #187 is built. Worktree isolation (#109) is now on main (the prior blocker), but --drain also
# needs dispatch timeout (#173) before it's safe for unattended loops. Single-pass is safe today.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

passthru=()
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) passthru+=(--dry-run); shift;;
  --repo)    export PL_REPO="$2"; shift 2;;   # via env — every reactor honors PL_REPO (dispatch has no --repo flag)
  --drain)   pl_die "cycle: --drain (#187) is not built yet — needs dispatch timeout (#173) before it is safe for unattended loops. Run cycle.sh (single pass) repeatedly for now.";;
  *)         pl_die "cycle: unknown arg $1";;
esac; done

TRIAGE_SH="${PL_TRIAGE_SH:-$here/triage-reviews.sh}"
DISPATCH_SH="${PL_DISPATCH_SH:-$here/dispatch.sh}"
INTEGRATE_SH="${PL_INTEGRATE_SH:-$here/integrate.sh}"
ACCEPT_SH="${PL_ACCEPT_SH:-$here/accept.sh}"

# Run one stage best-effort: log it, never let its failure abort the whole pass.
stage() {
  local label="$1" sh="$2"; shift 2
  echo "${PL_C_HEAD}cycle: ── ${label} ───────────────────────────────${PL_C_RST}" >&2
  if ! "$sh" "$@"; then
    echo "${PL_C_WARN}cycle: ${label} exited non-zero — continuing the pass (next stage)${PL_C_RST}" >&2
  fi
}

echo "${PL_C_HEAD}cycle: one full SDLC pass (triage-reviews → dispatch → integrate → accept)${PL_C_RST}" >&2
stage "triage-reviews" "$TRIAGE_SH"    ${passthru[@]+"${passthru[@]}"}
stage "dispatch"       "$DISPATCH_SH"  ${passthru[@]+"${passthru[@]}"}
stage "integrate"      "$INTEGRATE_SH" ${passthru[@]+"${passthru[@]}"}
stage "accept"         "$ACCEPT_SH"    ${passthru[@]+"${passthru[@]}"}
echo "${PL_C_OK}cycle: pass complete${PL_C_RST}" >&2
exit 0
