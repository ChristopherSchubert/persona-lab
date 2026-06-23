#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

cmd="${1:?usage: queue.sh <file|comment|label|close|query> ...}"; shift

# comment envelope: header line + body + collapsed provenance footer
pl_envelope() { # persona tier type body
  local persona="$1" tier="$2" rtype="$3" body="$4"
  printf '🤖 **%s** (%s) · %s\n\n%s\n\n<details><summary>AI persona — not the human</summary>\n%s · %s\n</details>\n' \
    "$persona" "$tier" "$rtype" "$body" "$persona ($tier)" "$(date -u +%FT%TZ)"
}

case "$cmd" in
  file)
    persona="" tier="" rtype="FINDING" title="" body=""
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --title) title="$2"; shift 2;;
      --body) body="$2"; shift 2;; *) pl_die "unknown arg $1";; esac; done
    [ -n "$title" ] || pl_die "file requires --title"
    gh issue create --title "$title" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")"
    ;;
  *) pl_die "verb $cmd not implemented yet";;
esac
