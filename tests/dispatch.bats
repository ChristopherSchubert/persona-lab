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
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
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
    {"number":5,"title":"old low","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p2"}]},
    {"number":9,"title":"new high","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p0"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#9" "$PL_CLAUDE_LOG"
  if grep -qF "#5" "$PL_CLAUDE_LOG"; then false; fi
}

@test "dispatch: equal priority breaks ties by oldest issue number" {
  fake_issues '[
    {"number":20,"title":"newer","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p1"}]},
    {"number":12,"title":"older","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p1"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#12" "$PL_CLAUDE_LOG"
  if grep -qF "#20" "$PL_CLAUDE_LOG"; then false; fi
}

@test "dispatch: writer persona claims the lock before dispatch and releases after" {
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
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
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
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
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
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
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
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

# ── Multi-dispatch per cycle (issue #45, Tom's PROPOSAL/DECISION) ──────────────────────
# Reader/consultant issues (is_writer_persona=false) dispatch up to PL_READONLY_CAP
# concurrently with NO lock; the writer issue stays serialized (one, foreground, locked).

@test "dispatch: default cap=1 dispatches exactly one reader (today's behaviour)" {
  # Two ready readers, no PL_READONLY_CAP → default 1 → exactly one dispatched.
  fake_issues '[
    {"number":51,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p1"}]},
    {"number":52,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p2"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  [ "$(grep -c CLAUDE "$PL_CLAUDE_LOG")" -eq 1 ]
  # highest priority (p1, #51) wins the single slot
  grep -qF "#51" "$PL_CLAUDE_LOG"
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
  # MUTATION PROOF: drop "| .[0:cap]" (dispatch all readers) → count becomes 2, this fails.
}

@test "dispatch: PL_READONLY_CAP=3 with 4 ready readers dispatches exactly 3, no lock" {
  fake_issues '[
    {"number":61,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p1"}]},
    {"number":62,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]},
    {"number":63,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:marketing"},{"name":"priority:p2"}]},
    {"number":64,"title":"r4","labels":[{"name":"state:ready"},{"name":"persona:release-engineer"},{"name":"priority:p3"}]}
  ]'
  PL_READONLY_CAP=3 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  [ "$(grep -c CLAUDE "$PL_CLAUDE_LOG")" -eq 3 ]
  # the three highest-priority readers, not the p3 straggler
  grep -qF "#61" "$PL_CLAUDE_LOG"
  grep -qF "#62" "$PL_CLAUDE_LOG"
  grep -qF "#63" "$PL_CLAUDE_LOG"
  if grep -qF "#64" "$PL_CLAUDE_LOG"; then false; fi
  # NO writer lock claimed for any reader
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
  # MUTATION PROOF: hardcode cap=1 (ignore PL_READONLY_CAP) → count becomes 1, this fails.
}

@test "dispatch: readers run concurrently (overlap in time), not serialized" {
  # Each reader appends START on entry, sleeps, then appends END. If dispatched
  # concurrently, all three STARTs land before any END (race-free: append-only, no
  # read-modify-write). Serial execution would interleave START,END,START,END,…
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
echo START >> "$PL_CONC_LOG"
sleep 0.5
echo END >> "$PL_CONC_LOG"
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  export PL_CONC_LOG="$(mktemp)"
  fake_issues '[
    {"number":71,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p1"}]},
    {"number":72,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]},
    {"number":73,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:marketing"},{"name":"priority:p1"}]}
  ]'
  PL_READONLY_CAP=3 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  first_three="$(head -3 "$PL_CONC_LOG")"
  rm -f "$PL_CONC_LOG"
  # all three readers entered (3 STARTs) before any finished — proves overlap.
  # serial dispatch would yield START\nEND\nSTART as the first three lines.
  [ "$first_three" = "$(printf 'START\nSTART\nSTART')" ]
  # MUTATION PROOF: drop the "&" (dispatch readers in foreground) → first three lines
  # become START,END,START, this fails.
}

@test "dispatch: writer + readers in one cycle — readers dispatched AND the one writer with lock" {
  fake_issues '[
    {"number":80,"title":"writer","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p1"}]},
    {"number":81,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]},
    {"number":82,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:marketing"},{"name":"priority:p1"}]}
  ]'
  PL_READONLY_CAP=3 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # the writer dispatched
  grep -qF "agents/developer.md" "$PL_CLAUDE_LOG"
  grep -qF "#80" "$PL_CLAUDE_LOG"
  # both readers dispatched too — same cycle
  grep -qF "#81" "$PL_CLAUDE_LOG"
  grep -qF "#82" "$PL_CLAUDE_LOG"
  # exactly one writer-lock claim (the writer), and a release
  [ "$(grep -c claim "$PL_LOCK_LOG")" -eq 1 ]
  grep -q "release" "$PL_LOCK_LOG"
  # MUTATION PROOF: skip the writer partition (readers only) → "#80"/claim absent, this fails.
}

@test "dispatch: at most ONE writer per cycle even when two writer issues are ready" {
  fake_issues '[
    {"number":90,"title":"w1","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p1"}]},
    {"number":91,"title":"w2","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p2"}]}
  ]'
  PL_READONLY_CAP=5 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # only the higher-priority writer, exactly one claim
  grep -qF "#90" "$PL_CLAUDE_LOG"
  if grep -qF "#91" "$PL_CLAUDE_LOG"; then false; fi
  [ "$(grep -c claim "$PL_LOCK_LOG")" -eq 1 ]
  # MUTATION PROOF: take writers with [0:cap] instead of [0:1] → #91 dispatched, this fails.
}

@test "dispatch: PL_READONLY_HARD_CAP clamps an over-large PL_READONLY_CAP" {
  # 5 ready readers, cap asks for 5, but hard cap = 2 → exactly 2 dispatched.
  fake_issues '[
    {"number":101,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p1"}]},
    {"number":102,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]},
    {"number":103,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:marketing"},{"name":"priority:p1"}]},
    {"number":104,"title":"r4","labels":[{"name":"state:ready"},{"name":"persona:release-engineer"},{"name":"priority:p1"}]},
    {"number":105,"title":"r5","labels":[{"name":"state:ready"},{"name":"persona:security-analyst"},{"name":"priority:p1"}]}
  ]'
  PL_READONLY_CAP=5 PL_READONLY_HARD_CAP=2 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  [ "$(grep -c CLAUDE "$PL_CLAUDE_LOG")" -eq 2 ]
  # MUTATION PROOF: drop the hard-cap clamp (use raw cap) → count becomes 5, this fails.
}

@test "dispatch: all background readers write run records before exit (no lost records)" {
  fake_issues '[
    {"number":111,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p1"}]},
    {"number":112,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]},
    {"number":113,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:marketing"},{"name":"priority:p1"}]}
  ]'
  PL_READONLY_CAP=3 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS_DIR" -name '*.ndjson' | head -1)"
  [ -n "$ndjson_file" ]
  # one dispatch record per reader issue — all present
  [ "$(grep -c '"trigger":"dispatch"' "$ndjson_file")" -eq 3 ]
  for n in 111 112 113; do
    grep -qF "\"issue_number\":$n" "$ndjson_file"
  done
}

@test "dispatch: the cycle blocks on its background readers before returning (final wait)" {
  # `wait` makes the parent block until every background reader finishes. The stub sleeps
  # 0.6s per reader; concurrent + waited ⇒ the whole cycle takes ≥0.6s. Without the final
  # `wait`, the parent returns near-instantly while readers run orphaned — exactly the
  # lost-records race in the real scheduler. (dispatch.sh runs each background reader with
  # its stdout/stderr closed off the parent pipe, so bats's `run` does not itself block on
  # the orphans — the elapsed time reflects the script's own `wait`, not the harness.)
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
sleep 0.6
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":131,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p1"}]},
    {"number":132,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]},
    {"number":133,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:marketing"},{"name":"priority:p1"}]}
  ]'
  start="$(date +%s%N)"
  PL_READONLY_CAP=3 run scripts/dispatch.sh
  end="$(date +%s%N)"
  [ "$status" -eq 0 ]
  elapsed_ms=$(( (end - start) / 1000000 ))
  # ≥ 500ms ⇒ the script waited for the 0.6s readers (concurrent, so not 1.8s).
  [ "$elapsed_ms" -ge 500 ]
  # MUTATION PROOF: remove the final `wait` → the parent returns in <500ms (readers
  # orphaned, records race the next cycle); elapsed drops below the floor, this fails.
}

# ── dev:ready gate for the writer (issue #37, Tom's design) ───────────────────────────
# `state:ready` = eligible for upstream reader work; `dev:ready` = upstream done, safe to
# build. The WRITER (developer) partition requires BOTH labels. Readers are unchanged:
# they still dispatch on `state:ready` alone, regardless of `dev:ready`.

@test "dispatch: writer issue with state:ready but NOT dev:ready is NOT dispatched" {
  fake_issues '[
    {"number":201,"title":"dev not ready","labels":[{"name":"state:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # nothing dispatched — the developer slot is gated by the missing dev:ready label
  if grep -q "CLAUDE" "$PL_CLAUDE_LOG"; then false; fi
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
  # MUTATION PROOF: drop the `dev:ready` clause from the writer filter → #201 dispatched
  # + claim appears, this fails.
}

@test "dispatch: writer issue with BOTH state:ready AND dev:ready IS dispatched (with lock)" {
  fake_issues '[
    {"number":202,"title":"dev ready","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "agents/developer.md" "$PL_CLAUDE_LOG"
  grep -qF "#202" "$PL_CLAUDE_LOG"
  grep -q "claim" "$PL_LOCK_LOG"
  grep -q "release" "$PL_LOCK_LOG"
  # MUTATION PROOF: require some other label instead of dev:ready in the writer filter →
  # #202 not dispatched, this fails.
}

@test "dispatch: reader dispatches on state:ready alone — dev:ready is irrelevant to readers" {
  # A reader with NO dev:ready still dispatches; the gate is writer-only.
  fake_issues '[
    {"number":203,"title":"reader no devready","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#203" "$PL_CLAUDE_LOG"
  grep -qF "agents/product-analyst.md" "$PL_CLAUDE_LOG"
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
  # MUTATION PROOF: add a dev:ready requirement to the reader filter → #203 not dispatched,
  # this fails.
}

@test "dispatch: dev:ready on a reader does not turn it into a writer (no lock, still reader)" {
  # Carrying dev:ready must not change a reader's classification or make it claim the lock.
  fake_issues '[
    {"number":204,"title":"reader with devready","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:technical-writer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#204" "$PL_CLAUDE_LOG"
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
}

@test "dispatch: mixed cycle — gated writer skipped, reader still flows" {
  # Writer lacks dev:ready (gated out); reader has only state:ready (dispatched). Proves the
  # gate is surgical: it removes the writer from the pool without starving readers.
  fake_issues '[
    {"number":205,"title":"writer gated","labels":[{"name":"state:ready"},{"name":"persona:developer"},{"name":"priority:p0"}]},
    {"number":206,"title":"reader","labels":[{"name":"state:ready"},{"name":"persona:marketing"},{"name":"priority:p1"}]}
  ]'
  PL_READONLY_CAP=3 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # writer #205 gated out — no dispatch, no lock
  if grep -qF "#205" "$PL_CLAUDE_LOG"; then false; fi
  if grep -q "claim" "$PL_LOCK_LOG"; then false; fi
  # reader #206 still dispatched
  grep -qF "#206" "$PL_CLAUDE_LOG"
}

@test "dispatch: multi-dispatch never calls the real claude binary either" {
  fake_issues '[
    {"number":121,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p1"}]},
    {"number":122,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]}
  ]'
  cat > "$PL_TEST_BIN/claude" <<'SH'
#!/usr/bin/env bash
echo "REAL CLAUDE CALLED" >> "$PL_CLAUDE_LOG"
exit 99
SH
  chmod +x "$PL_TEST_BIN/claude"
  PL_READONLY_CAP=2 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -q "REAL CLAUDE CALLED" "$PL_CLAUDE_LOG"; then false; fi
  # MUTATION PROOF: invoke `claude` directly instead of "$CLAUDE_BIN" → real-claude marker appears, this fails.
}

# ── Capacity enforced at the invocation (#9 governance fix) ────────────────────────────
# The fix: claude -p is launched with --allowedTools derived from the persona's `tools:`
# frontmatter (capacity-driven) and the agent file as the system prompt. So capacity is
# enforced at runtime, not merely advised — a reads-capacity persona cannot Edit/Write.

@test "dispatch: invocation scopes --allowedTools to a writer's capacity (includes Write)" {
  fake_issues '[
    {"number":11,"title":"dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF -- "--allowedTools" "$PL_CLAUDE_LOG"
  grep -qF "Write" "$PL_CLAUDE_LOG"
  # MUTATION PROOF: drop --allowedTools from the invocation → "Write" absent, this fails.
}

@test "dispatch: invocation scopes a reader read-only (no Write/Edit in --allowedTools)" {
  # product-analyst capacity = owns → Read,Grep,Glob — no Write/Edit. Enforced at invocation.
  fake_issues '[
    {"number":13,"title":"reader","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF -- "--allowedTools" "$PL_CLAUDE_LOG"
  grep -qF "Read" "$PL_CLAUDE_LOG"
  if grep -qE "Write|Edit" "$PL_CLAUDE_LOG"; then false; fi
  # MUTATION PROOF: pass the developer's tool set regardless of capacity → "Write" appears, this fails.
}

@test "dispatch: the persona file is applied as the system prompt (not passed as the prompt)" {
  fake_issues '[
    {"number":11,"title":"dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF -- "--append-system-prompt-file agents/developer.md" "$PL_CLAUDE_LOG"
  # MUTATION PROOF: revert to `claude -p "$agent" "$prompt"` → this flag is absent, this fails.
}
