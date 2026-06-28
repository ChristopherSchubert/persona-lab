#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
runs="$(pl_runs_dir)"; mkdir -p "$runs"
[ "${1:-}" = "append" ] || pl_die "usage: runlog.sh append --persona .. --repo .. --trigger .. --outcome .. [--tokens N] [--role R] [--action A] [--record-type T] [--artifact-url U] [--parent-id P] [--issue-number N]"
shift
persona="" repo="" trigger="" outcome="" tokens=0
role="" action="" record_type="" artifact_url="" parent_id="" issue_number=""
while [ $# -gt 0 ]; do case "$1" in
  --persona)      persona="$2";      shift 2;;
  --repo)         repo="$2";         shift 2;;
  --trigger)      trigger="$2";      shift 2;;
  --outcome)      outcome="$2";      shift 2;;
  --tokens)       tokens="$2";       shift 2;;
  --role)         role="$2";         shift 2;;
  --action)       action="$2";       shift 2;;
  --record-type)  record_type="$2";  shift 2;;
  --artifact-url) artifact_url="$2"; shift 2;;
  --parent-id)    parent_id="$2";    shift 2;;
  --issue-number) issue_number="$2"; shift 2;;
  *) pl_die "unknown arg $1";;
esac; done

# Build the record with required fields; add optional fields only when non-empty.
# issue_number is stored as a number (argjson); all others are strings.
jq -nc \
  --arg ts "$(date -u +%FT%TZ)" \
  --arg p "$persona" \
  --arg r "$repo" \
  --arg tr "$trigger" \
  --arg o "$outcome" \
  --argjson tok "$tokens" \
  --arg role "$role" \
  --arg action "$action" \
  --arg record_type "$record_type" \
  --arg artifact_url "$artifact_url" \
  --arg parent_id "$parent_id" \
  --arg issue_number "$issue_number" \
  '{ts:$ts, persona:$p, repo:$r, trigger:$tr, outcome:$o, cost_tokens:$tok}
   + (if $role         != "" then {role:$role}                   else {} end)
   + (if $action       != "" then {action:$action}               else {} end)
   + (if $record_type  != "" then {record_type:$record_type}     else {} end)
   + (if $artifact_url != "" then {artifact_url:$artifact_url}   else {} end)
   + (if $parent_id    != "" then {parent_id:$parent_id}         else {} end)
   + (if $issue_number != "" then {issue_number:($issue_number|tonumber)} else {} end)' \
  >> "$runs/$(date -u +%F).ndjson"
