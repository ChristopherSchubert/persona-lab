#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
runs="$(pl_runs_dir)"; mkdir -p "$runs"

subcmd="${1:-}"
case "$subcmd" in
  append) ;;
  update) ;;
  *) pl_die "usage: runlog.sh append --persona .. --repo .. --trigger .. --outcome .. [--tokens N] [--role R] [--action A] [--record-type T] [--artifact-url U] [--parent-id P] [--issue-number N]
       runlog.sh update --id <id> [--outcome O] [--tokens N] [--role R] [--action A] [--record-type T] [--artifact-url U]";;
esac
shift

if [ "$subcmd" = "append" ]; then
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

  # Generate a unique run_id: timestamp + 8 random hex chars.
  run_id="run-$(date -u +%Y%m%dT%H%M%SZ)-$(set +o pipefail; LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c8)"

  # Build the record with required fields; add optional fields only when non-empty.
  # issue_number is stored as a number (argjson); all others are strings.
  jq -nc \
    --arg run_id "$run_id" \
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
    '{run_id:$run_id, ts:$ts, persona:$p, repo:$r, trigger:$tr, outcome:$o, cost_tokens:$tok}
     + (if $role         != "" then {role:$role}                   else {} end)
     + (if $action       != "" then {action:$action}               else {} end)
     + (if $record_type  != "" then {record_type:$record_type}     else {} end)
     + (if $artifact_url != "" then {artifact_url:$artifact_url}   else {} end)
     + (if $parent_id    != "" then {parent_id:$parent_id}         else {} end)
     + (if $issue_number != "" then {issue_number:($issue_number|tonumber)} else {} end)' \
    >> "$runs/$(date -u +%F).ndjson"

  # Print the run_id so callers can capture it for a later update.
  printf '%s\n' "$run_id"

else  # update

  run_id="" outcome="" tokens="" role="" action="" record_type="" artifact_url=""
  while [ $# -gt 0 ]; do case "$1" in
    --id)           run_id="$2";       shift 2;;
    --outcome)      outcome="$2";      shift 2;;
    --tokens)       tokens="$2";       shift 2;;
    --role)         role="$2";         shift 2;;
    --action)       action="$2";       shift 2;;
    --record-type)  record_type="$2";  shift 2;;
    --artifact-url) artifact_url="$2"; shift 2;;
    *) pl_die "unknown arg $1";;
  esac; done

  [ -n "$run_id" ] || pl_die "runlog.sh update: --id is required"

  # Find the NDJSON file containing this run_id (search newest-first: today → older).
  target_file=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if jq -e --arg id "$run_id" 'select(.run_id == $id)' "$f" >/dev/null 2>&1; then
      target_file="$f"; break
    fi
  done < <(find "$runs" -maxdepth 1 -name '*.ndjson' 2>/dev/null | sort -r)
  [ -n "$target_file" ] || pl_die "runlog.sh update: run_id '$run_id' not found"

  # Atomically rewrite the file, merging new fields into the matching record.
  tmp="$(mktemp "${target_file}.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  jq -c \
    --arg id "$run_id" \
    --arg outcome "$outcome" \
    --arg tokens "$tokens" \
    --arg role "$role" \
    --arg action "$action" \
    --arg record_type "$record_type" \
    --arg artifact_url "$artifact_url" \
    'if .run_id == $id then
       .
       + (if $outcome      != "" then {outcome:$outcome}                       else {} end)
       + (if $tokens       != "" then {cost_tokens:($tokens|tonumber)}         else {} end)
       + (if $role         != "" then {role:$role}                             else {} end)
       + (if $action       != "" then {action:$action}                         else {} end)
       + (if $record_type  != "" then {record_type:$record_type}               else {} end)
       + (if $artifact_url != "" then {artifact_url:$artifact_url}             else {} end)
     else . end' "$target_file" > "$tmp" && mv "$tmp" "$target_file"

fi
