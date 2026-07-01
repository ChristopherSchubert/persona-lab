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
rounds_set=0
drain=0
while [ $# -gt 0 ]; do case "$1" in
  --dry-run)  passthru+=(--dry-run); shift;;
  --repo)     export PL_REPO="$2"; shift 2;;
  --rounds)   [ $# -ge 2 ] || pl_die "cycle: --rounds requires a value"
              [[ "${2}" =~ ^[0-9]+$ ]] && [ "${2}" -gt 0 ] || pl_die "cycle: --rounds requires a positive integer (got '${2}')"
              rounds="${2}"; rounds_set=1; shift 2;;
  --drain)    drain=1; shift;;
  *)          pl_die "cycle: unknown arg $1";;
esac; done

# Mutual-exclusion checks post-parse (require full argument set to be collected first).
[ "$drain" = "1" ] && [ "${#passthru[@]}" -gt 0 ] && pl_die "cycle: --drain is incompatible with --dry-run (dry-run never mutates labels, so _ready_count never reaches 0)"
[ "$drain" = "1" ] && [ "$rounds_set" = "1" ] && pl_die "cycle: --drain and --rounds are mutually exclusive"

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

# Count state:ready issues. Exits non-zero on gh failure so the drain loop aborts rather than
# silently treating a transient gh error as "quiescence". The || echo 0 pattern would be a
# false-complete trap: drain prints "drain complete" on a network blip and exits 0.
_ready_count() {
  local n
  n="$(gh issue list --repo "$(pl_gh_repo)" --label "state:ready" --json number --jq 'length' 2>/dev/null)" \
    || { echo "${PL_C_ERR}cycle: gh failed in _ready_count — cannot determine drain quiescence${PL_C_RST}" >&2; return 1; }
  printf '%s' "$n"
}

pass=0
while true; do
  pass=$((pass + 1))
  if [ "$drain" = "1" ]; then
    # Pre-pass snapshot count (informational only — triage may promote more issues during the pass).
    pre_count="$(_ready_count)" || pl_die "cycle: gh error in pre-pass count — aborting drain"
    echo "${PL_C_HEAD}cycle: pass ${pass} (draining — ${pre_count} state:ready before this pass)${PL_C_RST}" >&2
  else
    echo "${PL_C_HEAD}cycle: pass ${pass} of ${rounds}${PL_C_RST}" >&2
  fi

  stage "triage-reviews" "$TRIAGE_SH"    ${passthru[@]+"${passthru[@]}"}
  stage "dispatch"       "$DISPATCH_SH"  ${passthru[@]+"${passthru[@]}"}
  stage "integrate"      "$INTEGRATE_SH" ${passthru[@]+"${passthru[@]}"}
  stage "accept"         "$ACCEPT_SH"    ${passthru[@]+"${passthru[@]}"}
  echo "${PL_C_OK}cycle: pass ${pass} complete${PL_C_RST}" >&2

  if [ "$drain" = "1" ]; then
    remaining="$(_ready_count)" || pl_die "cycle: gh error checking remaining state:ready — aborting drain to avoid false-complete"
    if [ "$remaining" -eq 0 ]; then
      echo "${PL_C_OK}cycle: drain complete — no state:ready issues remain${PL_C_RST}" >&2
      break
    fi
    max_passes="${PL_DRAIN_MAX_PASSES:-20}"
    if [ "$pass" -ge "$max_passes" ]; then
      pl_die "cycle: --drain safety cap reached (${max_passes} passes, ${remaining} state:ready remain); set PL_DRAIN_MAX_PASSES to override"
    fi
  else
    [ "$pass" -lt "$rounds" ] || break
  fi
done
exit 0
