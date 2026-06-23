#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
map="$here/../config/capability-map.json"
case "${1:-}" in
  tools-for) jq -r --arg c "$2" '.[$c] | join(", ")' "$map";;
  *) pl_die "usage: assert-access.sh tools-for <capacity>";;
esac
