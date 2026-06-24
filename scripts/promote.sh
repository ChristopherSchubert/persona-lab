#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

new=""
while [ $# -gt 0 ]; do case "$1" in
  --add-repo) new="$2"; shift 2;; *) pl_die "promote: unknown arg $1";; esac; done

[ -n "$new" ] || pl_die "promote: --add-repo <name> required"

# Validate repo name: only [A-Za-z0-9_.-], no '..'
case "$new" in
  *[!A-Za-z0-9_.-]*) pl_die "promote: invalid repo name '$new'";;
  *..*) pl_die "promote: invalid repo name '$new' (contains ..)";;
esac

mf="$(pl_config_dir)/manifest.yml"
[ -f "$mf" ] || pl_die "promote: manifest not found at $mf"

grain="$(yq -r .grain "$mf")"

if [ "$grain" = "single" ]; then
  # Promote single -> platform: replace scalar repo with repos list
  export NEW="$new"
  yq -i '.grain="platform" | .repos = [.repo, strenv(NEW)] | del(.repo)' "$mf"
elif [ "$grain" = "platform" ]; then
  # Idempotent append to existing repos list
  export NEW="$new"
  already="$(yq -r '.repos | contains([strenv(NEW)])' "$mf")"
  if [ "$already" != "true" ]; then
    yq -i '.repos += [strenv(NEW)]' "$mf"
  fi
else
  pl_die "promote: unrecognised grain '$grain'"
fi

# Verify result is valid YAML
yq . "$mf" >/dev/null || pl_die "promote: produced invalid yaml"

echo "promoted $mf (grain=platform, added $new)"
