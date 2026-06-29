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

# ── stale-lock recovery (issue #8) ────────────────────────────────────────────
# Interrupted-dispatch simulation: a writer lock minted in the past with no live
# run, left orphaned because the EXIT trap never fired (hard kill).

setup_locks() {
  export PL_GH_STATE="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

@test "reclaim-locks: detects a stale lock, files an issue, leaves writes unblocked" {
  setup_locks
  # mint a lock dated 90 minutes ago (interrupted dispatch left it behind)
  PL_GH_FAKE_DATE="$(date -u -v-90M +%FT%TZ 2>/dev/null || date -u -d '90 minutes ago' +%FT%TZ)" \
    scripts/lock.sh claim --repo finances --holder Doug >/dev/null
  run scripts/watchdog.sh reclaim-locks --grace-min 30
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "RECLAIMED"
  echo "$output" | grep -q "finances"
  echo "$output" | grep -qi "issues/"          # an incident issue was filed
  # an archive of the orphaned lock was preserved
  echo "$output" | grep -q "persona-lock-archive/finances/"
  # end state: the lock is FREE — every further write is unblocked
  [ "$(scripts/lock.sh status --repo finances)" = "free" ]
}

@test "reclaim-locks: a fresh (active) lock is NOT reclaimed" {
  setup_locks
  scripts/lock.sh claim --repo finances --holder Doug >/dev/null   # dated now
  run scripts/watchdog.sh reclaim-locks --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "RECLAIMED"; then false; fi
  [ "$(scripts/lock.sh status --repo finances)" = "held" ]
}

@test "reclaim-locks: no locks present is a clean no-op" {
  setup_locks
  run scripts/watchdog.sh reclaim-locks --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "RECLAIMED"; then false; fi
}
