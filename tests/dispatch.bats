# dispatch.bats — one cycle: pick the single highest-ready dispatchable issue, run it, record it, stop.
#
# gh is stubbed; the issue list is supplied as JSON via PL_FAKE_ISSUES so the selection
# logic is exercised deterministically without a network. claude is stubbed via PL_CLAUDE
# so NO real model call is ever made.
setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  export PL_CLAUDE_LOG="$(mktemp)"
  export PL_LOCK_LOG="$(mktemp)"
  export PL_FAKE_ISSUES="$(mktemp)"

  # gh stub: `issue list --json …` echoes PL_FAKE_ISSUES; everything else is logged.
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "issue list") cat "$PL_FAKE_ISSUES";;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"

  # claude stub (selected via PL_CLAUDE): record argv so tests can assert what WOULD run.
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  export PL_CLAUDE="$PL_TEST_BIN/fake-claude"

  # lock.sh stub on PATH so claim/release are observable and never hit the network.
  # dispatch.sh calls it by absolute path (scripts/lock.sh); override via PL_LOCK_SH.
  cat > "$PL_TEST_BIN/fake-lock" <<'SH'
#!/usr/bin/env bash
echo "LOCK $*" >> "$PL_LOCK_LOG"
echo "fencesha000000000000000000000000000000000"
SH
  chmod +x "$PL_TEST_BIN/fake-lock"
  export PL_LOCK_SH="$PL_TEST_BIN/fake-lock"
  export PL_REPO="persona-lab"
}
teardown() {
  rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_CLAUDE_LOG" "$PL_LOCK_LOG" \
         "$PL_FAKE_ISSUES" "${PL_RUNS_DIR%/runs}"
}

# Helper: write a fake issue list (JSON array of {number,title,labels:[{name}]}).
fake_issues() { printf '%s' "$1" > "$PL_FAKE_ISSUES"; }

@test "dispatch: picks the single ready issue that has a persona label" {
  fake_issues '[
    {"number":10,"title":"no persona","labels":[{"name":"state:ready"}]},
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -q "CLAUDE" "$PL_CLAUDE_LOG"
  grep -qF "agents/developer.md" "$PL_CLAUDE_LOG"
  grep -qF "#11" "$PL_CLAUDE_LOG"
  # only ONE dispatch per cycle (no chaining)
  [ "$(grep -c CLAUDE "$PL_CLAUDE_LOG")" -eq 1 ]
}

@test "dispatch: picks higher priority first (priority:p0 beats older p2)" {
  fake_issues '[
    {"number":5,"title":"old low","labels":[{"name":"state:ready"},{"name":"persona:developer"},{"name":"priority:p2"}]},
    {"number":9,"title":"new high","labels":[{"name":"state:ready"},{"name":"persona:developer"},{"name":"priority:p0"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#9" "$PL_CLAUDE_LOG"
  if grep -qF "#5" "$PL_CLAUDE_LOG"; then false; fi
}

@test "dispatch: equal priority breaks ties by oldest issue number" {
  fake_issues '[
    {"number":20,"title":"newer","labels":[{"name":"state:ready"},{"name":"persona:developer"},{"name":"priority:p1"}]},
    {"number":12,"title":"older","labels":[{"name":"state:ready"},{"name":"persona:developer"},{"name":"priority:p1"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#12" "$PL_CLAUDE_LOG"
  if grep -qF "#20" "$PL_CLAUDE_LOG"; then false; fi
}

@test "dispatch: writer persona claims the lock before dispatch and releases after" {
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -q "claim" "$PL_LOCK_LOG"
  grep -q "release" "$PL_LOCK_LOG"
}

@test "dispatch: read-only persona does NOT claim the writer lock" {
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -q "CLAUDE" "$PL_CLAUDE_LOG"
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
}

@test "dispatch: writes a run record (trigger=dispatch) for the dispatched issue" {
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS_DIR" -name '*.ndjson' | head -1)"
  [ -n "$ndjson_file" ]
  record="$(tail -1 "$ndjson_file")"
  echo "$record" | jq -e '.trigger == "dispatch"'
  echo "$record" | jq -e '.issue_number == 11'
  echo "$record" | jq -e '.persona == "developer"'
}

@test "dispatch: --dry-run prints the target but invokes nothing" {
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "11"
  echo "$output" | grep -qF "developer"
  # nothing actually invoked
  if grep -q "CLAUDE" "$PL_CLAUDE_LOG"; then false; fi
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
  # and no run record written
  if find "$PL_RUNS_DIR" -name '*.ndjson' | grep -q .; then false; fi
}

@test "dispatch: skips persona-less ready issues and exits 0 (logs why)" {
  fake_issues '[
    {"number":10,"title":"no persona","labels":[{"name":"state:ready"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -q "CLAUDE" "$PL_CLAUDE_LOG"; then false; fi
  echo "$output" | grep -qiF "skip"
}

@test "dispatch: nothing ready exits 0 quietly (no invocation, no record)" {
  fake_issues '[]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -q "CLAUDE" "$PL_CLAUDE_LOG"; then false; fi
  if find "$PL_RUNS_DIR" -name '*.ndjson' | grep -q .; then false; fi
}

@test "dispatch: ignores blocked/needs-human issues even with a persona label" {
  fake_issues '[
    {"number":14,"title":"parked","labels":[{"name":"state:ready"},{"name":"persona:developer"},{"name":"blocked-by:decision"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -q "CLAUDE" "$PL_CLAUDE_LOG"; then false; fi
}

@test "dispatch: never calls the real claude binary (uses PL_CLAUDE indirection)" {
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"persona:developer"}]}
  ]'
  # Drop a poisoned `claude` on PATH; if dispatch honors PL_CLAUDE it is never called.
  cat > "$PL_TEST_BIN/claude" <<'SH'
#!/usr/bin/env bash
echo "REAL CLAUDE CALLED" >> "$PL_CLAUDE_LOG"
exit 99
SH
  chmod +x "$PL_TEST_BIN/claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -q "REAL CLAUDE CALLED" "$PL_CLAUDE_LOG"; then false; fi
}
