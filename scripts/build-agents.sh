#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
out="agents"; [ "${1:-}" = "--out" ] && out="$2"
mkdir -p "$out"; disc="$here/../docs/personas/_disciplines.md"
for b in "$here"/../docs/personas/*.md; do
  base="$(basename "$b" .md)"
  case "$base" in _*|owner|human) continue;; esac
  cap="$(pl_manifest_get "engagement.${base}.capacity" 2>/dev/null || echo reads)"
  [ -n "$cap" ] || cap="reads"
  tools="$("$here/assert-access.sh" tools-for "$cap" 2>/dev/null || "$here/assert-access.sh" tools-for reads)"
  { printf -- "---\nname: %s\ntools: %s\n---\n\n" "$base" "$tools"
    cat "$b"; printf "\n\n## Shared disciplines\n\n"; cat "$disc"; } > "$out/$base.md"
done
echo "built $(ls "$out" | wc -l | tr -d ' ') agents"
