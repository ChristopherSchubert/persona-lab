#!/usr/bin/env bash
# validate-run-record.sh <json-string>
# Validates a single NDJSON record against config/schemas/run-record.json constraints.
# Uses jq only — no external schema-validation tool needed; the schema's constraints
# (5 required string fields + 1 optional number) are fully expressible in jq.
# Exits 0 if valid, 1 with an error message if not.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: validate-run-record.sh <json-string>" >&2
  exit 1
fi

record="$1"

# Validate the record is parseable JSON first.
if ! echo "$record" | jq -e . >/dev/null 2>&1; then
  echo "validate-run-record: not valid JSON" >&2
  exit 1
fi

# Check all required fields exist and have the correct types.
# Schema: ts/persona/repo/trigger/outcome must be strings; cost_tokens must be a number if present.
errors="$(echo "$record" | jq -r '
  [
    (if (.run_id | type) != "string"   then "run_id must be a string (got \(.run_id | type))"   else empty end),
    (if (.ts | type) != "string"       then "ts must be a string (got \(.ts | type))"       else empty end),
    (if (.persona | type) != "string"  then "persona must be a string (got \(.persona | type))"  else empty end),
    (if (.repo | type) != "string"     then "repo must be a string (got \(.repo | type))"     else empty end),
    (if (.trigger | type) != "string"  then "trigger must be a string (got \(.trigger | type))"  else empty end),
    (if (.outcome | type) != "string"  then "outcome must be a string (got \(.outcome | type))"  else empty end),
    (if has("cost_tokens") and ((.cost_tokens | type) != "number")
       then "cost_tokens must be a number (got \(.cost_tokens | type))"
       else empty end)
  ] | .[]
')"

if [ -n "$errors" ]; then
  echo "validate-run-record: schema violation(s):" >&2
  echo "$errors" >&2
  exit 1
fi
