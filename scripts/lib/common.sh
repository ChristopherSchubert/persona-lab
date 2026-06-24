#!/usr/bin/env bash
# Shared helpers. Source this; do not execute.
set -euo pipefail

pl_repo_root() { git rev-parse --show-toplevel; }

pl_config_dir() { echo "${PL_CONFIG_DIR:-$(pl_repo_root)/.claude/persona-lab}"; }

# Read a scalar from the manifest (yq if present, else a grep fallback for top-level only).
pl_manifest_get() {
  local key="$1" mf; mf="$(pl_config_dir)/manifest.yml"
  if command -v yq >/dev/null 2>&1; then
    yq -r ".${key} // \"\"" "$mf"
  else
    # Fallback handles top-level scalars only; nested (dotted) keys require yq — fail closed.
    if [[ "$key" == *.* ]]; then
      pl_die "pl_manifest_get: nested key '$key' requires yq (brew install yq)"
    fi
    grep -E "^${key}:[[:space:]]" "$mf" | head -1 | sed -E "s/^${key}:[[:space:]]*///"
  fi
}

pl_die() { echo "persona-lab: $*" >&2; exit 1; }
