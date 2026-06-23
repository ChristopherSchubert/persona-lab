#!/usr/bin/env bash
# Writer lock via create-only Git ref (persona-lock/<repo>).
# Lock object = real branch pointing to a dedicated lock commit whose
# lock.json carries {holder, claimed_at, fence} where fence = that commit's own SHA.
# Release = delete ref.  verify-fence does a fresh re-read and compares.
# NO --force, NO PATCH, NO update — create-only CAS.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

cmd="${1:?usage: lock.sh <claim|release|status|verify-fence> --repo R [--holder H] [--fence F]}"; shift

repo="" holder="" fence=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   repo="$2";  shift 2;;
    --holder) holder="$2"; shift 2;;
    --fence)  fence="$2"; shift 2;;
    *) shift;;
  esac
done

[ -n "$repo" ] || pl_die "lock.sh: --repo required"
case "$repo" in *[!A-Za-z0-9_.-]*|*..*) pl_die "lock.sh: invalid repo name '$repo'";; esac
if [ -n "$holder" ]; then
  case "$holder" in *[!A-Za-z0-9_.\ -]*) pl_die "lock.sh: invalid holder '$holder'";; esac
fi

ref="refs/heads/persona-lock/${repo}"

case "$cmd" in
  claim)
    [ -n "$holder" ] || pl_die "claim needs --holder"
    lj="$(jq -nc --arg h "$holder" --arg t "$(date -u +%FT%TZ)" \
            '{holder:$h, claimed_at:$t}')"
    blob="$(gh api -X POST "repos/{owner}/{repo}/git/blobs" \
              -f content="$lj" -f encoding=utf-8 -q .sha)"
    tree="$(gh api -X POST "repos/{owner}/{repo}/git/trees" \
              -f 'tree[][path]=lock.json' \
              -f 'tree[][mode]=100644' \
              -f 'tree[][type]=blob' \
              -f "tree[][sha]=$blob" \
              -q .sha)"
    commit="$(gh api -X POST "repos/{owner}/{repo}/git/commits" \
                -f message="persona-lock $repo by $holder" \
                -f tree="$tree" \
                -q .sha)"
    if gh api -X POST "repos/{owner}/{repo}/git/refs" \
         -f ref="$ref" -f sha="$commit" >/dev/null 2>&1; then
      echo "$commit"
    else
      pl_die "lock held for $repo (claim refused — never force)"
    fi
    ;;

  verify-fence)
    [ -n "$fence" ] || pl_die "verify-fence needs --fence"
    cur="$(gh api "repos/{owner}/{repo}/git/${ref}" -q .object.sha 2>/dev/null || true)"
    [ "$cur" = "$fence" ] || \
      pl_die "fence mismatch (lock reclaimed) — abort the integrate, checkpoint instead"
    ;;

  release)
    gh api -X DELETE "repos/{owner}/{repo}/git/${ref}" >/dev/null 2>&1 || true
    echo "released $repo"
    ;;

  status)
    gh api "repos/{owner}/{repo}/git/${ref}" >/dev/null 2>&1 && echo "held" || echo "free"
    ;;

  *)
    pl_die "unknown lock cmd $cmd"
    ;;
esac
