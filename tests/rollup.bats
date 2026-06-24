#!/usr/bin/env bats
# P4A tests for scripts/rollup.sh

setup() {
  export PL_RUNS="$(mktemp -d)"; f="$PL_RUNS/2026-06-24.ndjson"
  printf '%s\n' \
    '{"ts":"t1","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"acted","cost_tokens":1000}' \
    '{"ts":"t2","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"acted","cost_tokens":500}' \
    '{"ts":"t3","persona":"Nina","repo":"r","trigger":"summon","outcome":"slept","cost_tokens":50}' > "$f"
}
teardown() { rm -rf "$PL_RUNS"; }

@test "rollup: aggregates per persona/outcome + total tokens" {
  run scripts/rollup.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Sam"
  echo "$output" | grep -Eq "acted.*2|2.*acted"   # Sam acted x2
  echo "$output" | grep -q "1550"                  # total cost_tokens
}

@test "rollup: empty run-log is clean (no error)" {
  rm -f "$PL_RUNS"/*.ndjson
  run scripts/rollup.sh; [ "$status" -eq 0 ]
}
