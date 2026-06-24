#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
out="agents"; [ "${1:-}" = "--out" ] && out="$2"
mkdir -p "$out"; disc="$here/../docs/personas/_disciplines.md"
mf="$(pl_config_dir)/manifest.yml"
for b in "$here"/../docs/personas/*.md; do
  base="$(basename "$b" .md)"
  case "$base" in _*|owner|human) continue;; esac
  if [ -f "$mf" ]; then
    if command -v yq >/dev/null 2>&1; then
      cap="$(pl_manifest_get "engagement.${base}.capacity")"
      if [ -z "$cap" ]; then
        echo "skipped $base (not in roster)"; continue
      fi
    else
      pl_die "build-agents: manifest present but capacity for '$base' unreadable — is yq installed?"
    fi
  else
    cap="reads"
  fi
  tools="$("$here/assert-access.sh" tools-for "$cap")"
  { printf -- "---\nname: %s\ntools: %s\n---\n\n" "$base" "$tools"
    cat "$b"; printf "\n\n"; cat "$disc"; } > "$out/$base.md"
done
echo "built $(ls "$out" | wc -l | tr -d ' ') agents"
