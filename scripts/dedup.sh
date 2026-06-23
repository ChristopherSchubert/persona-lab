#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
ledger="${PL_LEDGER:-$(pl_config_dir)/fingerprints}"; mkdir -p "$ledger"
[ "${1:-}" = "check" ] || pl_die "usage: dedup.sh check --persona .. --rule .. --path .. --snippet .."
shift; persona="" rule="" path="" snippet=""
while [ $# -gt 0 ]; do case "$1" in
  --persona) persona="$2"; shift 2;; --rule) rule="$2"; shift 2;;
  --path) path="$2"; shift 2;; --snippet) snippet="$2"; shift 2;; *) pl_die "unknown arg $1";; esac; done
norm="$(echo "$snippet" | tr '[:upper:]' '[:lower:]' | tr -s ' ')"
fp="$(printf '%s|%s|%s|%s' "$persona" "$rule" "$path" "$norm" | shasum -a 256 | cut -d' ' -f1)"
if [ -f "$ledger/$fp" ]; then echo "dup:$fp"; else echo "$(date -u +%FT%TZ)" > "$ledger/$fp"; echo "new:$fp"; fi
