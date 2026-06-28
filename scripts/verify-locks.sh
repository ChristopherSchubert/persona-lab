#!/usr/bin/env bash
# verify-locks.sh — audit the access model encoded in the agent `tools:` frontmatter.
#
# Three tiers (see config/capability-map.json + config/doc-writers.txt):
#   - developer (sole CODE writer)         : Write + Edit + Bash
#   - doc-writers (config/doc-writers.txt) : Write + Edit, and NO Bash (Bash+Write = code writer)
#   - every other agent                    : neither Write nor Edit
# An empty/absent doc-writers roster reduces to the original developer-only model.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

dir="agents"
doc_writers_file="${PL_DOC_WRITERS:-$here/../config/doc-writers.txt}"
while [ $# -gt 0 ]; do case "$1" in
  --dir)         dir="$2"; shift 2;;
  --doc-writers) doc_writers_file="$2"; shift 2;;
  *) pl_die "verify-locks: unknown arg $1";;
esac; done

dev="$dir/developer.md"
[ -f "$dev" ] || pl_die "verify-locks: $dev not found"

_tools() { sed -n 's/^tools:[[:space:]]*//p' "$1" | head -1; }
_has()   { case "$1" in *"$2"*) return 0;; *) return 1;; esac; }

# Load the committed doc-writers roster (slugs); missing file => empty set (dev-only model).
doc_writers=""
[ -f "$doc_writers_file" ] && doc_writers="$(sed 's/#.*//' "$doc_writers_file" | tr -d '[:blank:]' | grep -v '^$' || true)"
is_doc_writer() { printf '%s\n' "$doc_writers" | grep -qxF "$1"; }

# Developer = sole code writer: Write + Edit + Bash.
dt="$(_tools "$dev")"
_has "$dt" Write || pl_die "verify-locks: developer missing 'Write' — access-lock degraded"
_has "$dt" Edit  || pl_die "verify-locks: developer missing 'Edit' — access-lock degraded"
_has "$dt" Bash  || pl_die "verify-locks: developer missing 'Bash' — code-writer lock degraded"

violations=""
for f in "$dir"/*.md; do
  slug="$(basename "$f" .md)"
  [ "$slug" = "developer" ] && continue
  t="$(_tools "$f")"
  if is_doc_writer "$slug"; then
    _has "$t" Write || violations="$violations $f(doc-writer missing Write)"
    _has "$t" Edit  || violations="$violations $f(doc-writer missing Edit)"
    _has "$t" Bash  && violations="$violations $f(doc-writer must NOT have Bash)"
  else
    _has "$t" Write && violations="$violations $f(unexpected Write)"
    _has "$t" Edit  && violations="$violations $f(unexpected Edit)"
  fi
done

[ -z "$violations" ] || pl_die "verify-locks: access-lock violation(s):$violations"
echo "access locks OK"
