#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
map="$here/../config/capability-map.json"
case "${1:-}" in
  tools-for)
    out="$(jq -r --arg c "$2" 'if has($c) then .[$c]|join(", ") else "PL_UNKNOWN" end' "$map")"
    [ "$out" = "PL_UNKNOWN" ] && pl_die "assert-access: unknown capacity '$2'"
    echo "$out" ;;
  *) pl_die "usage: assert-access.sh tools-for <capacity>";;
esac
