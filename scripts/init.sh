#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
repo="" owner="" personas="" force=0
while [ $# -gt 0 ]; do case "$1" in
  --repo) repo="$2"; shift 2;; --owner) owner="$2"; shift 2;;
  --personas) personas="$2"; shift 2;; --force) force=1; shift;; *) pl_die "init: unknown arg $1";; esac; done
[ -n "$repo" ] && [ -n "$owner" ] && [ -n "$personas" ] || pl_die "init: --repo --owner --personas required"
case "$repo" in *[!A-Za-z0-9_.-]*) pl_die "init: invalid repo '$repo'";; esac
cfg="$(pl_config_dir)"; mf="$cfg/manifest.yml"; mkdir -p "$cfg"
[ -f "$mf" ] && [ "$force" -eq 0 ] && pl_die "init: $mf exists (use --force)"
{
  echo "grain: single"
  echo "owner: $owner"
  echo "bus: github-issues"
  echo "repo: $repo"
  echo "engagement:"
  capmap="$(pl_repo_root)/config/capability-map.json"
  IFS=','; for p in $personas; do
    name="${p%%:*}"; cap="${p##*:}"
    case "$name" in *[!a-z-]*) pl_die "init: invalid persona '$name'";; esac
    jq -e --arg c "$cap" 'has($c)' "$capmap" >/dev/null 2>&1 \
      || pl_die "init: unknown capacity '$cap' for '$name' — valid: writes, owns, audits, advises, reads"
    printf '  %s: { capacity: %s }\n' "$name" "$cap"
  done; unset IFS
  echo "oversight:"
  echo "  autonomy: conservative"
  echo "  visibility: minimal"
} > "$mf"
yq . "$mf" >/dev/null || pl_die "init: produced invalid yaml"
echo "wrote $mf"
