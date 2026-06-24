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
echo "done."
