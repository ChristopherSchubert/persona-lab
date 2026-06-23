#!/usr/bin/env bash
# Shared helpers. Source this; do not execute.
set -euo pipefail

pl_repo_root() { git rev-parse --show-toplevel; }

pl_config_dir() { echo "$(pl_repo_root)/.claude/persona-lab"; }

# Read a top-level scalar from the manifest (yq if present, else a grep fallback).
pl_manifest_get() {
  local key="$1" mf; mf="$(pl_config_dir)/manifest.yml"
  if command -v yq >/dev/null 2>&1; then yq -r ".${key} // \"\"" "$mf"; else
    grep -E "^${key}:" "$mf" | head -1 | sed -E "s/^${key}:[[:space:]]*//"; fi
}

pl_die() { echo "persona-lab: $*" >&2; exit 1; }
