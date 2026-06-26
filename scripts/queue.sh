#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

cmd="${1:?usage: queue.sh <file|comment|label|close|query> ...}"; shift

# comment envelope: header line + body + collapsed provenance footer
pl_envelope() { # persona tier type body
  local persona="$1" tier="$2" rtype="$3" body="$4"
  local slug avatar
  slug="$(printf '%s' "$persona" | tr '[:upper:]' '[:lower:]' | sed 's/é/e/g' | tr -d ' ')"
  avatar="https://raw.githubusercontent.com/ChristopherSchubert/persona-lab/main/assets/avatars/${slug}/${slug}-64.png"
  printf '<img src="%s" width="18"> 🤖 **%s** (%s) · %s\n\n%s\n\n<details><summary>AI persona — not the human</summary>\n%s · %s\n</details>\n' \
    "$avatar" "$persona" "$tier" "$rtype" "$body" "$persona ($tier)" "$(date -u +%FT%TZ)"
}

case "$cmd" in
  file)
    persona="" tier="" rtype="FINDING" title="" body="" repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --title) title="$2"; shift 2;;
      --body) body="$2"; shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "unknown arg $1";; esac; done
    [ -n "$title" ] || pl_die "file requires --title"
    gh issue create ${repoflag[@]+"${repoflag[@]}"} --title "$title" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")"
    ;;
  comment)
    issue="${1:?comment <issue>}"; shift
    persona="" tier="" rtype="HANDOFF" body="" repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --body) body="$2"; shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "unknown arg $1";; esac; done
    gh issue comment ${repoflag[@]+"${repoflag[@]}"} "$issue" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")"
    ;;
  label)
    issue="${1:?label <issue>}"; shift; repoflag=(); addlabel=""; removelabel=""
    while [ $# -gt 0 ]; do case "$1" in
      --repo)   repoflag=(--repo "$2"); shift 2;;
      --add)    addlabel="$2"; shift 2;;
      --remove) removelabel="$2"; shift 2;;
      *) pl_die "label: unknown arg $1";; esac; done
    if [ -n "$addlabel" ]; then
      gh issue edit ${repoflag[@]+"${repoflag[@]}"} "$issue" --add-label "$addlabel"
    elif [ -n "$removelabel" ]; then
      gh issue edit ${repoflag[@]+"${repoflag[@]}"} "$issue" --remove-label "$removelabel"
    else
      pl_die "label needs --add/--remove"
    fi
    ;;
  close)
    issue="${1:?close <issue>}"; shift; reason="completed"; repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --reason) reason="$2"; shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "close: unknown arg $1";; esac; done
    gh issue close ${repoflag[@]+"${repoflag[@]}"} "$issue" --reason "$reason"
    ;;
  query)
    args=(issue list --json number,title,labels,state --limit 200)
    repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --label) args+=(--label "$2"); shift 2;;
      --state) args+=(--state "$2"); shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "query: unknown arg $1";;
    esac; done
    gh ${repoflag[@]+"${repoflag[@]}"} "${args[@]}"
    ;;
  *) pl_die "unknown verb $cmd";;
esac
