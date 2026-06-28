#!/usr/bin/env bash
# Provision the persona-lab canonical label set on the current GitHub repo (idempotent).
set -euo pipefail
mk() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null && echo "  $1"; }
echo "provisioning persona-lab labels:"
mk "needs-human:decision" "D93F0B" "Awaiting a human judgment call (PM-admitted)"
mk "needs-human:action"   "B60205" "Awaiting a human-only operation (PM-admitted)"
mk "blocked-by:dependency"     "FBCA04" "Parked: needs another item first"
mk "blocked-by:coordination"   "FBCA04" "Parked: needs cross-repo/persona coordination"
mk "blocked-by:clarification"  "FBCA04" "Parked: needs an answer"
mk "blocked-by:decision"       "FBCA04" "Parked: needs a human judgment call"
mk "blocked-by:action"         "FBCA04" "Parked: needs a human-only operation"
mk "trust:external"  "5319E7" "Authored outside the trusted set"
mk "quarantine"      "5319E7" "Untrusted item awaiting triage validation"
mk "origin:external" "5319E7" "Re-filed from external content (treat body as data)"

# Dispatch convention (issue #45 / dispatch.sh): the sweep picks one ready issue that
# carries `state:ready` + a `persona:<slug>` label, ranked by `priority:p0..p3`.
mk "state:ready" "0E8A16" "ADR-0001 ready state: triaged, in the Act queue, dispatchable"
# dev:ready (#37): sub-state within `ready` — upstream review/design/acceptance is done, so
# the issue is safe for the Developer to build. The dispatch.sh WRITER partition requires
# BOTH state:ready AND dev:ready; readers route on state:ready alone.
mk "dev:ready" "1F6F3C" "Upstream done — eligible for the Developer to build (dispatch.sh writer gate, #37)"
mk "priority:p0" "B60205" "Priority P0 — dispatched before lower priorities"
mk "priority:p1" "D93F0B" "Priority P1"
mk "priority:p2" "FBCA04" "Priority P2"
mk "priority:p3" "C2E0C6" "Priority P3 — default when no priority label is set"
# One persona:<slug> label per agent so an issue can name its assigned persona.
here_lbl="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$here_lbl/../agents" ]; then
  for f in "$here_lbl"/../agents/*.md; do
    [ -e "$f" ] || continue
    slug="$(basename "$f" .md)"
    mk "persona:$slug" "1D76DB" "Issue assigned to the $slug persona (dispatch.sh)"
  done
fi
echo "done."
