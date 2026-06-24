#!/usr/bin/env bash
# rollup.sh — deterministic run-log summary (pure jq, no model)
# Reads all *.ndjson under ${PL_RUNS:-$(pl_config_dir)/runs} and prints:
#   - per-persona/outcome counts (sorted)
#   - total cost_tokens across all records
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

runs="${PL_RUNS:-$(pl_config_dir)/runs}"

# Collect all ndjson files; if none exist, print empty summary and exit cleanly
files=()
if [ -d "$runs" ]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$runs" -maxdepth 1 -name '*.ndjson' -print0 2>/dev/null | sort -z)
fi

if [ "${#files[@]}" -eq 0 ]; then
  printf 'persona-lab run-log rollup\n'
  printf 'no run records found\n'
  printf 'total cost_tokens: 0\n'
  exit 0
fi

cat "${files[@]}" 2>/dev/null | jq -rs '
  # slurp all records into one array
  . as $recs
  | {
      by_persona: (
        $recs
        | group_by(.persona)
        | map({
            persona: .[0].persona,
            outcomes: (
              group_by(.outcome)
              | map({ outcome: .[0].outcome, count: length })
              | sort_by(.outcome)
            )
          })
        | sort_by(.persona)
      ),
      total_cost_tokens: ($recs | map(.cost_tokens // 0) | add // 0)
    }
  | "persona-lab run-log rollup",
    "────────────────────────────────────────",
    (.by_persona[] |
      "  \(.persona):",
      (.outcomes[] | "    \(.outcome): \(.count)")
    ),
    "────────────────────────────────────────",
    "total cost_tokens: \(.total_cost_tokens)"
'
