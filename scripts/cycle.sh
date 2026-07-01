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
# --rounds N  run exactly N passes (default 1)
# --drain     loop to quiescence: keep passing until no state:ready issues remain (#187)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

passthru=()
rounds=1
drain=0
while [ $# -gt 0 ]; do case "$1" in
  --dry-run)  passthru+=(--dry-run); shift;;
  --repo)     export PL_REPO="$2"; shift 2;;
  --rounds)   rounds="$2"; shift 2;;
  --drain)    drain=1; shift;;
  *)          pl_die "cycle: unknown arg $1";;
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

_ready_count() {
  gh issue list --repo "$(pl_gh_repo)" --label "state:ready" --json number --jq 'length' 2>/dev/null || echo 0
}

pass=0
while true; do
  pass=$((pass + 1))
  if [ "$drain" = "1" ]; then
    echo "${PL_C_HEAD}cycle: pass ${pass} (draining — $(  _ready_count) state:ready)${PL_C_RST}" >&2
  else
    echo "${PL_C_HEAD}cycle: pass ${pass} of ${rounds}${PL_C_RST}" >&2
  fi

  stage "triage-reviews" "$TRIAGE_SH"    ${passthru[@]+"${passthru[@]}"}
  stage "dispatch"       "$DISPATCH_SH"  ${passthru[@]+"${passthru[@]}"}
  stage "integrate"      "$INTEGRATE_SH" ${passthru[@]+"${passthru[@]}"}
  stage "accept"         "$ACCEPT_SH"    ${passthru[@]+"${passthru[@]}"}
  echo "${PL_C_OK}cycle: pass ${pass} complete${PL_C_RST}" >&2

  if [ "$drain" = "1" ]; then
    remaining="$(_ready_count)"
    if [ "$remaining" -eq 0 ]; then
      echo "${PL_C_OK}cycle: drain complete — no state:ready issues remain${PL_C_RST}" >&2
      break
    fi
  else
    [ "$pass" -lt "$rounds" ] || break
  fi
done
exit 0
