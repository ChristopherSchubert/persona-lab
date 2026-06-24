#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
runs="${PL_RUNS:-$(pl_config_dir)/runs}"; mkdir -p "$runs"
[ "${1:-}" = "append" ] || pl_die "usage: runlog.sh append --persona .. --repo .. --trigger .. --outcome .. [--tokens N]"
shift; persona="" repo="" trigger="" outcome="" tokens=0
while [ $# -gt 0 ]; do case "$1" in
  --persona)  persona="$2";  shift 2;;
  --repo)     repo="$2";     shift 2;;
  --trigger)  trigger="$2";  shift 2;;
  --outcome)  outcome="$2";  shift 2;;
  --tokens)   tokens="$2";   shift 2;;
  *) pl_die "unknown arg $1";;
esac; done
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg p "$persona" --arg r "$repo" \
  --arg tr "$trigger" --arg o "$outcome" --argjson tok "$tokens" \
  '{ts:$ts, persona:$p, repo:$r, trigger:$tr, outcome:$o, cost_tokens:$tok}' \
  >> "$runs/$(date -u +%F).ndjson"
