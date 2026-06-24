#!/usr/bin/env bash
# assign-names.sh <persona-slug> <repo>
# Prints a single deterministic name for the given persona+repo pair.
# Platform singletons return their fixed name (repo arg ignored).
# Repo-tier personas deterministically pick from their pool.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

slug="${1:-}"
repo="${2:-}"

if [[ -z "$slug" ]]; then
  pl_die "usage: assign-names.sh <persona-slug> <repo>"
fi

# Map slug to display title used in the pool file
case "$slug" in
  developer)          title="Developer" ;;
  product-analyst)    title="Product Analyst" ;;
  security-analyst)   title="Security Analyst" ;;
  design-analyst)     title="Design Analyst" ;;
  product-manager)    title="Product Manager" ;;
  lead-engineer)      title="Lead Engineer" ;;
  platform-architect) title="Platform Architect" ;;
  data-architect)     title="Data Architect" ;;
  head-of-security)   title="Head of Security" ;;
  head-of-design)     title="Head of Design" ;;
  head-of-finops)     title="Head of FinOps" ;;
  *) pl_die "unknown persona slug: '$slug'" ;;
esac

root="$(pl_repo_root)"
pool_file="${root}/docs/personas/_name-pools.md"

[[ -f "$pool_file" ]] || pl_die "pool file not found: $pool_file"

# Platform singletons — fixed name from the table, repo arg ignored
case "$slug" in
  product-manager|lead-engineer|platform-architect|data-architect|head-of-security|head-of-design|head-of-finops)
    # Extract from table row: | Role | Name |
    name="$(grep "| ${title} |" "$pool_file" | awk -F'|' '{print $3}' | tr -d ' ')"
    [[ -n "$name" ]] || pl_die "could not find fixed name for '$title' in $pool_file"
    printf '%s\n' "$name"
    exit 0
    ;;
esac

# Repo-tier personas — deterministic pick from pool
# Find the names line: the line immediately after "### <Title> —"
names_line="$(grep -A1 "^### ${title} " "$pool_file" | tail -1)"
[[ -n "$names_line" ]] || pl_die "could not find pool for '$title' in $pool_file"

# Split on ' · ' (space + middot U+00B7 + space) into a bash array
# Use a temp file to avoid subshell issues with IFS and arrays in bash 3.2
IFS=$'\n' read -r -d '' -a names_raw < <(
  printf '%s' "$names_line" | tr '·' '\n'
) || true

# Trim leading/trailing whitespace from each name and collect into array
names=()
for raw in "${names_raw[@]}"; do
  # trim leading and trailing spaces
  trimmed="${raw#"${raw%%[! ]*}"}"
  trimmed="${trimmed%"${trimmed##*[! ]}"}"
  [[ -n "$trimmed" ]] && names+=("$trimmed")
done

N="${#names[@]}"
[[ "$N" -gt 0 ]] || pl_die "pool for '$title' is empty"

# Deterministic index: hash(slug|repo) mod N
hash_hex="$(printf '%s' "${slug}|${repo}" | shasum -a 256 | cut -c1-8)"
idx=$(( 16#${hash_hex} % N ))

printf '%s\n' "${names[$idx]}"
