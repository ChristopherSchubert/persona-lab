#!/usr/bin/env bash
# Writer lock via create-only Git ref (persona-lock/<repo>).
# Lock object = real branch pointing to a dedicated lock commit whose
# lock.json carries {holder, claimed_at}; the fence = that commit's own SHA.
# Release = delete ref.  verify-fence does a fresh re-read and compares.
# NO --force, NO PATCH, NO update — create-only CAS.
#
# Recovery primitives (issue #8 — an interrupted Developer leaves an orphaned lock):
#   inspect    — {holder, claimed_at, fence} of the current lock (committer.date is claimed_at), or {}
#   list       — every live persona-lock/<repo> ref as "<repo>\t<fence>" (excludes the archive ns)
#   checkpoint — preserve the current lock commit under persona-lock-archive/<repo>/<fence> (create-only)
#   reclaim    — delete the stale ref then recreate a fresh one (create-only CAS, no force)
# The watchdog orchestrates assess→checkpoint→file-issue→reclaim; staleness policy lives there.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

cmd="${1:?usage: lock.sh <claim|release|status|verify-fence|inspect|list|checkpoint|reclaim> --repo R [--holder H] [--fence F]}"; shift

repo="" holder="" fence=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   repo="$2";  shift 2;;
    --holder) holder="$2"; shift 2;;
    --fence)  fence="$2"; shift 2;;
    *) shift;;
  esac
done

# `list` spans the whole persona-lock namespace, so it needs no --repo; everything else does.
if [ "$cmd" != "list" ]; then
  [ -n "$repo" ] || pl_die "lock.sh: --repo required"
  case "$repo" in *[!A-Za-z0-9_.-]*|*..*) pl_die "lock.sh: invalid repo name '$repo'";; esac
fi
if [ -n "$holder" ]; then
  case "$holder" in *[!A-Za-z0-9_.\ -]*) pl_die "lock.sh: invalid holder '$holder'";; esac
fi

ref="refs/heads/persona-lock/${repo}"

# ── shared Git Data primitives (create-only; no force, no update) ──────────────
_ref_sha() { gh api "repos/{owner}/{repo}/git/$1" -q .object.sha 2>/dev/null || true; }
_make_lock_commit() { # holder → commit sha
  local h="$1" lj blob tree
  lj="$(jq -nc --arg h "$h" --arg t "$(date -u +%FT%TZ)" '{holder:$h, claimed_at:$t}')"
  blob="$(gh api -X POST "repos/{owner}/{repo}/git/blobs" \
            -f content="$lj" -f encoding=utf-8 -q .sha)"
  tree="$(gh api -X POST "repos/{owner}/{repo}/git/trees" \
            -f 'tree[][path]=lock.json' -f 'tree[][mode]=100644' \
            -f 'tree[][type]=blob' -f "tree[][sha]=$blob" -q .sha)"
  gh api -X POST "repos/{owner}/{repo}/git/commits" \
    -f message="persona-lock $repo by $h" -f tree="$tree" -q .sha
}
_create_ref() { gh api -X POST "repos/{owner}/{repo}/git/refs" -f ref="$1" -f sha="$2" >/dev/null 2>&1; }

case "$cmd" in
  claim)
    [ -n "$holder" ] || pl_die "claim needs --holder"
    commit="$(_make_lock_commit "$holder")"
    if _create_ref "$ref" "$commit"; then
      echo "$commit"
    else
      pl_die "lock held for $repo (claim refused — never force)"
    fi
    ;;

  verify-fence)
    [ -n "$fence" ] || pl_die "verify-fence needs --fence"
    cur="$(_ref_sha "$ref")"
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

  inspect)
    cur="$(_ref_sha "$ref")"
    if [ -z "$cur" ]; then echo '{}'; exit 0; fi
    cj="$(gh api "repos/{owner}/{repo}/git/commits/$cur" 2>/dev/null || echo '{}')"
    claimed_at="$(printf '%s' "$cj" | jq -r '.committer.date // .author.date // ""')"
    msg="$(printf '%s' "$cj" | jq -r '.message // ""')"
    holder="${msg##*by }"; [ "$holder" = "$msg" ] && holder=""
    jq -nc --arg h "$holder" --arg t "$claimed_at" --arg f "$cur" \
      '{holder:$h, claimed_at:$t, fence:$f}'
    ;;

  list)
    gh api "repos/{owner}/{repo}/git/matching-refs/heads/persona-lock/" \
      --jq '.[] | "\(.ref)\t\(.object.sha)"' 2>/dev/null \
      | sed 's#^refs/heads/persona-lock/##'
    ;;

  checkpoint)
    cur="$(_ref_sha "$ref")"
    if [ -z "$cur" ]; then echo "free"; exit 0; fi
    archive="refs/heads/persona-lock-archive/${repo}/${cur}"
    _create_ref "$archive" "$cur" || true   # idempotent: fine if already archived
    echo "$archive"
    ;;

  reclaim)
    cur="$(_ref_sha "$ref")"
    if [ -z "$cur" ]; then echo "free"; exit 0; fi
    [ -n "$holder" ] || holder="watchdog-recovery"
    gh api -X DELETE "repos/{owner}/{repo}/git/${ref}" >/dev/null 2>&1 || true
    commit="$(_make_lock_commit "$holder")"
    if _create_ref "$ref" "$commit"; then
      echo "$commit"
    else
      pl_die "reclaim: re-create contended for $repo (a live writer re-claimed — already unblocked)"
    fi
    ;;

  *)
    pl_die "unknown lock cmd $cmd"
    ;;
esac
