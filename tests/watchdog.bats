#!/usr/bin/env bats
# P4B tests for scripts/watchdog.sh

setup() { export PL_RUNS="$(mktemp -d)"; }
teardown() { rm -rf "$PL_RUNS"; }

@test "watchdog: flags a stale pending wake" {
  old="$(date -u -v-90M +%FT%TZ 2>/dev/null || date -u -d '90 minutes ago' +%FT%TZ)"
  printf '{"ts":"%s","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"pending","cost_tokens":0}\n' "$old" > "$PL_RUNS/x.ndjson"
  run scripts/watchdog.sh scan --grace-min 30
  [ "$status" -eq 0 ]; echo "$output" | grep -qi "Sam"
}

@test "watchdog: a recent pending is NOT flagged" {
  now="$(date -u +%FT%TZ)"
  printf '{"ts":"%s","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"pending","cost_tokens":0}\n' "$now" > "$PL_RUNS/x.ndjson"
  run scripts/watchdog.sh scan --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -qi "Sam"; then false; fi
}

@test "watchdog: a terminal (acted) record is never flagged" {
  old="$(date -u -v-90M +%FT%TZ 2>/dev/null || date -u -d '90 minutes ago' +%FT%TZ)"
  printf '{"ts":"%s","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"acted","cost_tokens":10}\n' "$old" > "$PL_RUNS/x.ndjson"
  run scripts/watchdog.sh scan --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -qi "Sam"; then false; fi
}
