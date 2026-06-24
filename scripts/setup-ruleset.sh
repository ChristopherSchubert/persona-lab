#!/usr/bin/env bash
# Generate (or apply) the GitHub ruleset that protects the persona-lock/* branch namespace.
#
# Usage:
#   setup-ruleset.sh [--dry-run]   Print the JSON payload; do NOT call GitHub (default).
#   setup-ruleset.sh --apply       Print what would be POSTed, prompt for confirmation,
#                                  then refuse (deferred until the persona-system App id is
#                                  provisioned in Phase 4 outward).
#
# bypass_actors is intentionally empty in dry-run: the persona-system GitHub App id is
# added at live-apply time so the bot can create/delete/update persona-lock/* refs.
# Until that App is provisioned nothing can mutate persona-lock/* once the ruleset is
# active, which is why live apply is deferred.  Phase 1/3 rely on
# serialize-at-dispatch + the dispatch fence, NOT this ruleset.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
mode="dry-run"

for arg in "$@"; do
  case "$arg" in
    --dry-run) mode="dry-run" ;;
    --apply)   mode="apply"   ;;
    *)         pl_die "setup-ruleset: unknown argument '$arg'" ;;
  esac
done

# ---------------------------------------------------------------------------
# Build payload with jq (guarantees valid JSON — never hand-written strings)
# ---------------------------------------------------------------------------
PAYLOAD="$(jq -n '{
  name: "persona-lab-lock",
  target: "branch",
  enforcement: "active",
  conditions: {
    ref_name: {
      include: ["refs/heads/persona-lock/**"],
      exclude: []
    }
  },
  rules: [
    {type: "deletion"},
    {type: "non_fast_forward"},
    {type: "update"}
  ],
  bypass_actors: []
}')"

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$mode" in
  dry-run)
    echo "$PAYLOAD"
    exit 0
    ;;
  apply)
    echo "Would POST the following ruleset to: POST repos/{owner}/{repo}/rulesets" >&2
    echo "$PAYLOAD" >&2
    printf '\nConfirm apply? [y/N] ' >&2
    read -r answer
    case "$answer" in
      [Yy]) : ;;
      *)    pl_die "setup-ruleset: aborted by user" ;;
    esac
    # The persona-system GitHub App id is not yet provisioned (Phase 4 outward).
    # Performing a live apply now would lock persona-lock/* permanently with no
    # authorised bypass actor.  Defer until the App id is known.
    pl_die "setup-ruleset: live apply requires the persona-system App id (Phase 4 outward) — deferred"
    ;;
esac
