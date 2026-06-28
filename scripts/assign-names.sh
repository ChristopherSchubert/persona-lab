#!/usr/bin/env bash
# assign-names.sh <persona-slug> [repo]
# Prints the single fixed name for the given persona role.
# Every role has exactly one person, identical across all repos. The optional
# repo argument is accepted for caller compatibility but ignored.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

slug="${1:-}"
# ${2:-} (repo) accepted but unused — one person per role, repo-independent.

if [[ -z "$slug" ]]; then
  pl_die "usage: assign-names.sh <persona-slug> [repo]"
fi

# Map slug to the display title used in the roster table
case "$slug" in
  developer)            title="Developer" ;;
  product-analyst)      title="Product Analyst" ;;
  security-analyst)     title="Security Analyst" ;;
  design-analyst)       title="Design Analyst" ;;
  qa-analyst)           title="QA Analyst" ;;
  technical-writer)     title="Technical Writer" ;;
  release-engineer)     title="Release Engineer" ;;
  product-manager)      title="Product Manager" ;;
  lead-engineer)        title="Lead Engineer" ;;
  platform-architect)   title="Platform Architect" ;;
  enterprise-architect) title="Enterprise Architect" ;;
  delivery-manager)     title="Delivery Manager" ;;
  data-architect)       title="Data Architect" ;;
  head-of-security)     title="Head of Security" ;;
  head-of-qa)           title="Head of QA" ;;
  head-of-design)       title="Head of Design" ;;
  finops)               title="FinOps" ;;
  marketing)            title="Marketing" ;;
  reliability-engineer)  title="Reliability Engineer" ;;
  accessibility-analyst) title="Accessibility Analyst" ;;
  privacy-analyst)       title="Privacy Analyst" ;;
  *) pl_die "unknown persona slug: '$slug'" ;;
esac

root="$(pl_repo_root)"
roster_file="${root}/docs/personas/_name-pools.md"
[[ -f "$roster_file" ]] || pl_die "roster file not found: $roster_file"

# One person per role — fixed name from the roster table row "| <Title> | <Name> |"
name="$(grep "| ${title} |" "$roster_file" | awk -F'|' '{print $3}' | tr -d ' ')"
[[ -n "$name" ]] || pl_die "could not find name for '$title' in $roster_file"
printf '%s\n' "$name"
