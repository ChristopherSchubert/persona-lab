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
  "issue view") echo "INJECTED_TASK_CONTEXT for issue $3";;
  "repo view")  echo "acme/persona-lab";;
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
  # Restore any agent files mutated by model-selection tests (guaranteed even on assertion failure).
  if [ -n "${_AGENT_RESTORE_FILE:-}" ] && [ -n "${_AGENT_RESTORE_TARGET:-}" ]; then
    cp "$_AGENT_RESTORE_FILE" "$_AGENT_RESTORE_TARGET"
    rm -f "$_AGENT_RESTORE_FILE"
    unset _AGENT_RESTORE_FILE _AGENT_RESTORE_TARGET
  fi
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
    {"number":52,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p2"}]}
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
    {"number":62,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p1"}]},
    {"number":63,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:privacy-analyst"},{"name":"priority:p2"}]},
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
    {"number":72,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p1"}]},
    {"number":73,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:privacy-analyst"},{"name":"priority:p1"}]}
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
    {"number":81,"title":"r1","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p1"}]},
    {"number":82,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:privacy-analyst"},{"name":"priority:p1"}]}
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
    {"number":102,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p1"}]},
    {"number":103,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:privacy-analyst"},{"name":"priority:p1"}]},
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
    {"number":112,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p1"}]},
    {"number":113,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:privacy-analyst"},{"name":"priority:p1"}]}
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
    {"number":132,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p1"}]},
    {"number":133,"title":"r3","labels":[{"name":"state:ready"},{"name":"persona:privacy-analyst"},{"name":"priority:p1"}]}
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
    {"number":204,"title":"reader with devready","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:accessibility-analyst"}]}
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
    {"number":206,"title":"reader","labels":[{"name":"state:ready"},{"name":"persona:privacy-analyst"},{"name":"priority:p1"}]}
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
    {"number":122,"title":"r2","labels":[{"name":"state:ready"},{"name":"persona:accessibility-analyst"},{"name":"priority:p1"}]}
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

# ── Harness posts the persona's record (#9 access-model fix, option 1) ─────────────────
# Most personas are read-only (no Bash) and cannot run queue.sh. So each persona RETURNS a
# record as JSON and the HARNESS posts it under the persona envelope. The claude stub emits
# the `--output-format json` envelope; `.result` carries the persona's record object.

@test "dispatch: harness posts a returned record to the bus on the persona's behalf" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"ASSESSMENT\\",\\"body\\":\\"analysis here\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # queue.sh comment -> gh issue comment on #13 with the record
  grep -qF "issue comment" "$PL_GH_LOG"
  grep -qF "13" "$PL_GH_LOG"
  grep -qF "ASSESSMENT" "$PL_GH_LOG"
  # MUTATION PROOF: drop the queue.sh post call → no "issue comment" logged, this fails.
}

@test "dispatch: the record is posted under the persona's resolved NAME, not the slug" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"DELIVERED\\",\\"body\\":\\"done\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":11,"title":"dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # envelope rendered with the developer's name (Doug), not the slug "developer"
  grep -qF "Doug" "$PL_GH_LOG"
  grep -qF "DELIVERED" "$PL_GH_LOG"
  # MUTATION PROOF: pass the slug as --persona instead of assign-names → "Doug" absent, this fails.
}

@test "dispatch: a persona returning no valid record posts nothing (graceful)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"I could not complete this, sorry."}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -q "CLAUDE" "$PL_CLAUDE_LOG"
  if grep -qF "issue comment" "$PL_GH_LOG"; then false; fi
  # MUTATION PROOF: post unconditionally without validating the record → "issue comment" appears, this fails.
}

@test "dispatch: an invalid record_type is rejected (no junk envelope on the bus)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"BOGUS\\",\\"body\\":\\"x\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -qF "issue comment" "$PL_GH_LOG"; then false; fi
  # MUTATION PROOF: drop the _valid_rtype gate → BOGUS is posted, this fails.
}

# ── Mutator serialization (#80 part 2) ────────────────────────────────────────────────
# Any persona granted Write/Edit (developer OR a doc-writer) is a "mutator" and must hold the
# writer lock — at most ONE per cycle — so concurrent edits can't clobber the working tree.
# The code writer (Write+Bash) is dev:ready-gated; doc-writers (Write, no Bash) are not.
# These read the REAL agent tools, so technical-writer/head-of-design must be doc-writes.

@test "dispatch: a doc-writer (Write, no Bash) holds the lock and needs NO dev:ready" {
  fake_issues '[
    {"number":300,"title":"doc fix","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#300" "$PL_CLAUDE_LOG"        # dispatched despite no dev:ready
  grep -q "claim" "$PL_LOCK_LOG"          # and it serialized on the lock
  grep -q "release" "$PL_LOCK_LOG"
  # MUTATION PROOF: treat only the developer as a mutator → technical-writer runs lock-free, fails.
}

@test "dispatch: at most ONE mutator per cycle (developer beats a lower-priority doc-writer)" {
  fake_issues '[
    {"number":301,"title":"code","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"},{"name":"priority:p0"}]},
    {"number":302,"title":"doc","labels":[{"name":"state:ready"},{"name":"persona:technical-writer"},{"name":"priority:p1"}]}
  ]'
  PL_READONLY_CAP=5 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#301" "$PL_CLAUDE_LOG"
  if grep -qF "#302" "$PL_CLAUDE_LOG"; then false; fi   # doc-writer not also run — slot is taken
  [ "$(grep -c claim "$PL_LOCK_LOG")" -eq 1 ]
  # MUTATION PROOF: allow multiple mutators → #302 also dispatched, this fails.
}

@test "dispatch: a gated (no dev:ready) developer yields the mutator slot to a ready doc-writer" {
  fake_issues '[
    {"number":303,"title":"code not ready","labels":[{"name":"state:ready"},{"name":"persona:developer"},{"name":"priority:p0"}]},
    {"number":304,"title":"doc","labels":[{"name":"state:ready"},{"name":"persona:head-of-design"},{"name":"priority:p1"}]}
  ]'
  PL_READONLY_CAP=5 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -qF "#303" "$PL_CLAUDE_LOG"; then false; fi   # developer gated out (no dev:ready)
  grep -qF "#304" "$PL_CLAUDE_LOG"                       # doc-writer takes the slot
  grep -q "claim" "$PL_LOCK_LOG"
  # MUTATION PROOF: gate doc-writers on dev:ready too → #304 not dispatched, this fails.
}

# ── Robust record parsing + raw-dump (parity with audit-sweep) ─────────────────────────

@test "dispatch: parses a record the model wrapped in prose (robust extraction)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"Here is my reply: {\\"record_type\\":\\"REPLY\\",\\"body\\":\\"the convention\\"} — hope that helps"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"ask","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "issue comment" "$PL_GH_LOG"   # the prose-wrapped record still posted
  grep -qF "REPLY" "$PL_GH_LOG"
  # MUTATION PROOF: drop the perl bracket fallback → prose-wrapped record unparsed, this fails.
}

@test "dispatch: dumps the raw output when the record won't parse (no silent drop)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"I am not sure how to format this, sorry."}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":11,"title":"dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "raw output"
  echo "$output" | grep -qF "I am not sure"   # the actual model text is surfaced (foreground mutator)
  if grep -qF "issue comment" "$PL_GH_LOG"; then false; fi
  # MUTATION PROOF: swallow the result on parse failure → "raw output" absent, this fails.
}

# ── Personas read the bus (#125): harness injects the issue into the prompt ─────────────

# ── State advance after a posted record (#132 treadmill fix) ──────────────────────────
# THE bug: after a persona's record is posted, the issue kept `state:ready` and was
# re-selected every cycle (a treadmill). The harness — the only actor with a shell — must
# drive the ADR-0001 state machine forward: remove `state:ready` so the same issue can't be
# re-picked, and set the next state from the record type. Personas have no Bash, so they
# cannot do this themselves.

@test "dispatch: a DELIVERED record advances the issue to in_review and off state:ready" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"DELIVERED\\",\\"body\\":\\"done; PR #9, CI green\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":11,"title":"dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "issue edit" "$PL_GH_LOG"
  grep -qF "state:in_review" "$PL_GH_LOG"
  grep -qF -- "--remove-label state:ready" "$PL_GH_LOG"
  # MUTATION PROOF: drop the advance_state call → no "issue edit"/"state:in_review", this fails.
}

@test "dispatch: a BLOCKER record parks the issue (off state:ready)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"BLOCKER\\",\\"body\\":\\"blocked: needs a decision\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "state:parked" "$PL_GH_LOG"
  grep -qF -- "--remove-label state:ready" "$PL_GH_LOG"
  # MUTATION PROOF: map BLOCKER to the default state → "state:parked" absent, this fails.
}

@test "dispatch: an ASK record parks the issue awaiting input (off state:ready)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"ASK\\",\\"body\\":\\"need clarification from PM\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "state:parked" "$PL_GH_LOG"
  grep -qF -- "--remove-label state:ready" "$PL_GH_LOG"
}

@test "dispatch: an ASSESSMENT record moves the issue to in_progress (off state:ready)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"ASSESSMENT\\",\\"body\\":\\"observed: X\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "state:in_progress" "$PL_GH_LOG"
  grep -qF -- "--remove-label state:ready" "$PL_GH_LOG"
  # MUTATION PROOF: leave state:ready in place (no advance) → treadmill; this fails.
}

@test "dispatch: a non-parseable response does NOT advance state (issue stays selectable)" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"I could not produce a record."}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # nothing posted ⇒ nothing advanced; the issue must stay state:ready for a real next attempt
  if grep -qF "issue edit" "$PL_GH_LOG"; then false; fi
  # MUTATION PROOF: advance unconditionally (not gated on a successful post) → "issue edit" appears, this fails.
}

@test "dispatch: injects the dispatched issue's content into the persona's prompt" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REPLY\\",\\"body\\":\\"ok\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "INJECTED_TASK_CONTEXT" "$PL_CLAUDE_LOG"   # the persona received its task, not just "issue #N"
  # MUTATION PROOF: drop pl_issue_context from the prompt → context absent, this fails.
}

# ── #195: a review verdict lands on the PR, not the issue ────────────────────────────────

@test "dispatch: REVIEW record naming a pr+verdict posts a PR review, not an issue comment" {
  # A review work item: the lead engineer is assigned to review PR #190.
  fake_issues '[
    {"number":192,"title":"Greg: code-review PR #190","labels":[{"name":"state:ready"},{"name":"persona:lead-engineer"},{"name":"priority:p0"}]}
  ]'
  # The reviewer returns a REVIEW verdict that names the PR and the verdict it reached.
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"pr\\":190,\\"verdict\\":\\"approve\\",\\"body\\":\\"Approved at eb4b9e4.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"

  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # #216: verdict posts to the PR as a COMMENT (never native --approve, which fails on own PR);
  # the gate is the LABEL applied from the verdict.
  grep -qE "pr review.*190.*--comment" "$PL_GH_LOG"
  if grep -qE "pr review.*190.*--approve" "$PL_GH_LOG"; then false; fi
  grep -qE "pr edit.*190.*--add-label gate:eng-approved" "$PL_GH_LOG"
  # And NOT buried as an issue comment on the review issue.
  if grep -qE "issue comment.*192" "$PL_GH_LOG"; then false; fi
  # The review TASK must advance off state:ready so it doesn't re-dispatch every cycle (#132 treadmill).
  grep -qF "state:in_review" "$PL_GH_LOG"
  grep -qF -- "--remove-label state:ready" "$PL_GH_LOG"
  # MUTATION PROOF: use native --approve → fails on own PR (#216); drop the gate label → integrate can't see the approval.
}

@test "dispatch: a request-changes verdict posts a comment and applies the blocking gate label" {
  fake_issues '[
    {"number":192,"title":"Greg: code-review PR #190","labels":[{"name":"state:ready"},{"name":"persona:lead-engineer"},{"name":"priority:p0"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"pr\\":190,\\"verdict\\":\\"request-changes\\",\\"body\\":\\"B1 must be fixed.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"

  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qE "pr review.*190.*--comment" "$PL_GH_LOG"
  if grep -qE "pr review.*190.*--request-changes" "$PL_GH_LOG"; then false; fi
  grep -qE "pr edit.*190.*--add-label gate:changes-requested" "$PL_GH_LOG"
  if grep -qE "issue comment.*192" "$PL_GH_LOG"; then false; fi
}

@test "dispatch: a REVIEW verdict of 'comment' maps to a plain gh pr review --comment" {
  fake_issues '[
    {"number":192,"title":"Greg: note on PR #190","labels":[{"name":"state:ready"},{"name":"persona:lead-engineer"},{"name":"priority:p0"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"pr\\":190,\\"verdict\\":\\"comment\\",\\"body\\":\\"One note, non-blocking.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"

  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qE "pr review.*190.*--comment" "$PL_GH_LOG"
  if grep -qE "issue comment.*192" "$PL_GH_LOG"; then false; fi
}

@test "dispatch: a non-PR record (no pr field) still posts as an issue comment" {
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"DELIVERED\\",\\"body\\":\\"Shipped.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"

  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qE "issue comment.*11" "$PL_GH_LOG"
  if grep -qE "pr review" "$PL_GH_LOG"; then false; fi
}

# ── Auto-apply merge-gate labels from a reviewer's verdict (#149/#196 — loop labels itself) ──────

@test "dispatch: lead-engineer approve verdict applies gate:eng-approved to the PR" {
  fake_issues '[
    {"number":192,"title":"Greg: review PR #190","labels":[{"name":"state:ready"},{"name":"persona:lead-engineer"},{"name":"priority:p0"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"pr\\":190,\\"verdict\\":\\"approve\\",\\"body\\":\\"LGTM.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qE "pr edit.*190.*--add-label gate:eng-approved" "$PL_GH_LOG"
}

@test "dispatch: head-of-qa approve verdict applies gate:qa-approved to the PR" {
  fake_issues '[
    {"number":193,"title":"Priya: QA PR #190","labels":[{"name":"state:ready"},{"name":"persona:head-of-qa"},{"name":"priority:p0"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"pr\\":190,\\"verdict\\":\\"approve\\",\\"body\\":\\"QA passed.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qE "pr edit.*190.*--add-label gate:qa-approved" "$PL_GH_LOG"
}

@test "dispatch: lead-engineer request-changes applies gate:changes-requested (and removes eng-approved)" {
  fake_issues '[
    {"number":192,"title":"Greg: review PR #190","labels":[{"name":"state:ready"},{"name":"persona:lead-engineer"},{"name":"priority:p0"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"pr\\":190,\\"verdict\\":\\"request-changes\\",\\"body\\":\\"Fix B1.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qE "pr edit.*190.*--add-label gate:changes-requested" "$PL_GH_LOG"
  grep -qE "pr edit.*190.*--remove-label gate:eng-approved" "$PL_GH_LOG"
}

@test "dispatch: a non-gating persona's PR review applies NO gate label" {
  fake_issues '[
    {"number":194,"title":"Analyst note on PR #190","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"},{"name":"priority:p0"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"pr\\":190,\\"verdict\\":\\"approve\\",\\"body\\":\\"Reads fine.\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -qE "pr edit.*gate:" "$PL_GH_LOG"; then false; fi
}

# ── Producing path stamps the Resolves-Issue trailer so accept.sh can close the issue (#149/#196) ──

@test "dispatch: the persona prompt instructs PRs to carry a Resolves-Issue trailer" {
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"{\\"record_type\\":\\"DELIVERED\\",\\"body\\":\\"done\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # the persona is told to stamp the trailer naming THIS issue, so a merged PR can be PM-accepted
  grep -qF "Resolves-Issue: #11" "$PL_CLAUDE_LOG"
}

# ── #217: forward progress on failure — a repeatedly-failing task is parked, not looped forever ──

@test "dispatch: an issue that has failed PL_MAX_FAILURES times is parked off state:ready" {
  fake_issues '[
    {"number":11,"title":"doomed","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  # seed two prior failures for #11 in the run-log; this run's failure makes three
  mkdir -p "$PL_RUNS_DIR"
  printf '%s\n%s\n' '{"issue_number":11,"outcome":"failed"}' '{"issue_number":11,"outcome":"failed"}' > "$PL_RUNS_DIR/seed.ndjson"
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"I cannot produce a record."}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qE "issue edit.*11.*--remove-label state:ready" "$PL_GH_LOG"
  # MUTATION PROOF: drop the park-on-failure guard → no "issue edit … --remove-label state:ready", this fails.
}

@test "dispatch: an issue failing for the first time is NOT parked (under the threshold)" {
  fake_issues '[
    {"number":11,"title":"flaky","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"I cannot produce a record."}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue edit.*11.*--remove-label state:ready" "$PL_GH_LOG"; then false; fi
}

# ── per-persona model selection (#234) ────────────────────────────────────────────────────────────

@test "dispatch: passes --model from agent frontmatter to claude -p" {
  # Save original into a temp file; teardown() restores it even if assertions fail.
  _AGENT_RESTORE_TARGET="agents/developer.md"
  _AGENT_RESTORE_FILE="$(mktemp)"
  cp "$_AGENT_RESTORE_TARGET" "$_AGENT_RESTORE_FILE"
  sed -i '' 's/^model:.*/model: claude-test-model-sentinel/' agents/developer.md

  fake_issues '[
    {"number":11,"title":"test model passthrough","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -q "CLAUDE" "$PL_CLAUDE_LOG"
  grep -qF -- "--model claude-test-model-sentinel" "$PL_CLAUDE_LOG"
}

@test "dispatch: omits --model flag when agent has no model: frontmatter" {
  # Save original into a temp file; teardown() restores it even if assertions fail.
  _AGENT_RESTORE_TARGET="agents/lead-engineer.md"
  _AGENT_RESTORE_FILE="$(mktemp)"
  cp "$_AGENT_RESTORE_TARGET" "$_AGENT_RESTORE_FILE"
  sed -i '' '/^model:/d' agents/lead-engineer.md

  fake_issues '[
    {"number":11,"title":"no model field","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:lead-engineer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  if grep -q -- "--model" "$PL_CLAUDE_LOG"; then false; fi
}

# ── Per-dispatch git worktree isolation (issue #109) ──────────────────────────────────
# Each MUTATOR dispatch runs in its OWN ephemeral worktree cut from a pinned origin/<default>
# on a fresh branch pl/<persona>/issue-<n>, so no dispatch ever inherits another's HEAD and
# concurrent mutators can't clobber a shared tree. Readers (read-only) get NONE. Reversible
# default: OFF unless PL_WORKTREE_ISOLATION=1 (mirrors PL_READONLY_CAP), so the existing tests
# above exercise the in-tree path unchanged. `git` is stubbed: the stub creates the worktree
# dir on `add` and removes it on `remove`, so cleanup is observable without a real checkout.

# Install a git stub that records argv and simulates worktree add/remove on disk.
_stub_git() {
  export PL_GIT_LOG="$(mktemp)"
  cat > "$PL_TEST_BIN/git" <<'SH'
#!/usr/bin/env bash
echo "GIT $*" >> "$PL_GIT_LOG"
# `worktree add --detach <path> <ref>`  → create the dir so the dispatch can cd into it
if [ "$1" = "worktree" ] && [ "$2" = "add" ]; then mkdir -p "$4"; fi
# `worktree remove --force <path>`       → remove it (proves cleanup ran)
if [ "$1" = "worktree" ] && [ "$2" = "remove" ]; then rm -rf "$4"; fi
exit 0
SH
  chmod +x "$PL_TEST_BIN/git"
}

@test "dispatch: worktree isolation is OFF by default (no git worktree for a writer)" {
  _stub_git
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#11" "$PL_CLAUDE_LOG"                       # still dispatched (in the shared tree)
  if grep -qF "worktree add" "$PL_GIT_LOG"; then false; fi
  # MUTATION PROOF: default PL_WORKTREE_ISOLATION to 1 → "worktree add" appears, this fails.
}

@test "dispatch: PL_WORKTREE_ISOLATION=1 runs a mutator in its own worktree off origin/main" {
  _stub_git
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  PL_WORKTREE_ISOLATION=1 PL_DEFAULT_BRANCH=main run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  # worktree cut from PINNED origin/main on a fresh per-issue branch — never another HEAD
  grep -qF "worktree add" "$PL_GIT_LOG"
  grep -qF "origin/main" "$PL_GIT_LOG"
  grep -qF "switch -c pl/developer/issue-11" "$PL_GIT_LOG"
  # and torn down afterward (the EXIT trap)
  grep -qF "worktree remove" "$PL_GIT_LOG"
  [ ! -d ".claude/persona-lab/wt/developer-11" ]
  # MUTATION PROOF: drop make_worktree/remove_worktree → "worktree add"/"remove" absent, this fails.
}

@test "dispatch: a reader gets NO worktree even with isolation on (mutator-gated)" {
  _stub_git
  fake_issues '[
    {"number":13,"title":"analysis","labels":[{"name":"state:ready"},{"name":"persona:product-analyst"}]}
  ]'
  PL_WORKTREE_ISOLATION=1 PL_DEFAULT_BRANCH=main run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  grep -qF "#13" "$PL_CLAUDE_LOG"                       # reader still dispatched
  if grep -qF "worktree add" "$PL_GIT_LOG"; then false; fi
  # MUTATION PROOF: create a worktree for every dispatch → "worktree add" appears, this fails.
}

@test "dispatch: the mutator's claude runs INSIDE the worktree (cwd = worktree)" {
  _stub_git
  export PL_PWD_LOG="$(mktemp)"
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
pwd >> "$PL_PWD_LOG"
printf '{"result":"{\\"record_type\\":\\"DELIVERED\\",\\"body\\":\\"done\\"}"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":11,"title":"ready dev","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  PL_WORKTREE_ISOLATION=1 PL_DEFAULT_BRANCH=main run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  cwd="$(tail -1 "$PL_PWD_LOG")"; rm -f "$PL_PWD_LOG"
  case "$cwd" in */.claude/persona-lab/wt/developer-11) ;; *) false;; esac
  # MUTATION PROOF: run claude in the shared tree (ignore the workdir) → cwd is the repo root, this fails.
}

@test "dispatch: PL_DISPATCH_TIMEOUT kills a hung claude and records outcome=failed" {
  # Provide a fake `timeout` in PL_TEST_BIN (macOS lacks the GNU coreutils version).
  cat > "$PL_TEST_BIN/timeout" <<'SH'
#!/usr/bin/env bash
dur=$1; shift
"$@" &
child=$!
( sleep "$dur"; kill "$child" 2>/dev/null ) &
killer=$!
wait "$child" 2>/dev/null; rc=$?
kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
exit $rc
SH
  chmod +x "$PL_TEST_BIN/timeout"
  # Replace fake-claude with a sleeper that never exits on its own.
  # exec so SIGTERM from fake-timeout hits sleep directly (no orphaned sleep child).
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
exec sleep 60
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  fake_issues '[
    {"number":5,"title":"slow task","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  # timeout after 1s — dispatch should NOT hang and should record a failed outcome
  PL_DISPATCH_TIMEOUT=1 run scripts/dispatch.sh
  [ "$status" -eq 0 ]  # dispatch itself exits cleanly even though claude was killed
  # lock was claimed and then released (cleanup ran)
  grep -qF "claim" "$PL_LOCK_LOG"
  grep -qF "release" "$PL_LOCK_LOG"
  # a run record was written with outcome=failed
  local ndjson="$PL_RUNS_DIR/$(date -u +%F).ndjson"
  [ -f "$ndjson" ]   # file must exist (runlog.sh wrote it); || true would mask a runlog failure
  local rec
  rec="$(jq -rc 'select(.outcome=="failed")' "$ndjson" | head -1)"
  [ -n "$rec" ]
  # MUTATION PROOF: remove timeout_args conditional → dispatch hangs on sleep 60, test times out.
}

@test "dispatch: warns when PL_DISPATCH_TIMEOUT set but timeout binary is absent" {
  # Remove timeout from PATH so command -v timeout fails.
  # The dispatch should proceed (no hang) and emit a warning to stderr.
  fake_issues '[
    {"number":5,"title":"quick task","labels":[{"name":"state:ready"},{"name":"dev:ready"},{"name":"persona:developer"}]}
  ]'
  # Remove the fake timeout if one was written from a prior test run in this session.
  rm -f "$PL_TEST_BIN/timeout"
  PL_DISPATCH_TIMEOUT=300 run scripts/dispatch.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE "PL_DISPATCH_TIMEOUT|timeout.*not found|coreutils"
  # MUTATION PROOF: remove the else-branch warning → output has no warning message, grep fails.
}
