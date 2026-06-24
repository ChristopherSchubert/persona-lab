#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

dir="agents"
while [ $# -gt 0 ]; do case "$1" in
  --dir) dir="$2"; shift 2;; *) pl_die "verify-locks: unknown arg $1";; esac; done

dev="$dir/developer.md"
[ -f "$dev" ] || pl_die "verify-locks: $dev not found"

# Positive assertion: developer MUST have both Write and Edit.
tools_line="$(sed -n 's/^tools:[[:space:]]*//p' "$dev" | head -1)"
case "$tools_line" in
  *Write*) ;;
  *) pl_die "verify-locks: $dev is missing 'Write' in its tools line — access-lock degraded";;
esac
case "$tools_line" in
  *Edit*) ;;
  *) pl_die "verify-locks: $dev is missing 'Edit' in its tools line — access-lock degraded";;
esac

# Negative assertion: no other agent may have Write or Edit.
violations=""
for f in "$dir"/*.md; do
  [ "$f" = "$dev" ] && continue
  t="$(sed -n 's/^tools:[[:space:]]*//p' "$f" | head -1)"
  case "$t" in
    *Write*|*Edit*)
      violations="$violations $f";;
  esac
done

[ -z "$violations" ] || pl_die "verify-locks: Write/Edit found in non-developer agent(s):$violations"

echo "access locks OK"
