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

# Resolve the directory where run records are written/read.
# Precedence: PL_RUNS_DIR (test-isolation override) > PL_RUNS (legacy override) > config default.
# Tests set PL_RUNS_DIR to a temp dir so they never pollute the real runs dir.
pl_runs_dir() { echo "${PL_RUNS_DIR:-${PL_RUNS:-$(pl_config_dir)/runs}}"; }

# W1 comment envelope: single-line float (img + name + badge), then `AI` · role, then body.
# Shared by queue.sh (issue comments/files) and review.sh (PR reviews/comments) so the
# bus and PR surfaces render identically. tier may be "Tier · Role" — only the Role shows.
pl_envelope() { # persona tier type body
  local persona="$1" tier="$2" rtype="$3" body="$4"
  local slug avatar role color
  slug="$(printf '%s' "$persona" | tr '[:upper:]' '[:lower:]' | sed 's/é/e/g' | tr -d ' ')"
  avatar="https://raw.githubusercontent.com/ChristopherSchubert/persona-lab/main/assets/avatars/${slug}/${slug}-64.png"
  role="${tier#* · }"; [ "$role" = "$tier" ] && role="$tier"
  case "$rtype" in
    PROPOSAL|ROUTING)             color=8b5cf6 ;;
    DECISION)                     color=2563eb ;;
    DELIVERED)                    color=16a34a ;;
    ASSESSMENT)                   color=f59e0b ;;
    HANDOFF)                      color=0891b2 ;;
    REVIEW)                       color=06b6d4 ;;
    BLOCKER|PUSHBACK)             color=dc2626 ;;
    FEEDBACK)                     color=14b8a6 ;;
    ASK)                          color=d946ef ;;
    REPLY)                        color=a855f7 ;;
    *)                            color=64748b ;;
  esac
  # Approved envelope: single-line float (img + name + badge), then `AI` · role. No <br clear>, no footer.
  printf '<img src="%s" width="44" align="left"> **%s** <img src="https://img.shields.io/badge/%s-%s?style=flat-square" height="16" align="texttop">\n`AI` · %s\n\n%s\n' \
    "$avatar" "$persona" "$rtype" "$color" "$role" "$body"
}

pl_die() { echo "persona-lab: $*" >&2; exit 1; }
