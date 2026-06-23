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
  comment)
    issue="${1:?comment <issue>}"; shift
    persona="" tier="" rtype="HANDOFF" body=""
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --body) body="$2"; shift 2;; *) pl_die "unknown arg $1";; esac; done
    gh issue comment "$issue" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")"
    ;;
  label)
    issue="${1:?label <issue>}"; shift
    case "$1" in
      --add)    gh issue edit "$issue" --add-label "$2";;
      --remove) gh issue edit "$issue" --remove-label "$2";;
      *) pl_die "label needs --add/--remove";;
    esac
    ;;
  close)
    issue="${1:?close <issue>}"; shift; reason="completed"
    [ "${1:-}" = "--reason" ] && reason="$2"
    gh issue close "$issue" --reason "$reason"
    ;;
  query)
    args=(issue list --json number,title,labels,state --limit 200)
    while [ $# -gt 0 ]; do case "$1" in
      --label) args+=(--label "$2"); shift 2;;
      --state) args+=(--state "$2"); shift 2;;
      *) pl_die "query: unknown arg $1";;
    esac; done
    gh "${args[@]}"
    ;;
  *) pl_die "unknown verb $cmd";;
esac
