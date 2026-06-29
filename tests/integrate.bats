# integrate.bats — the INTEGRATE pass (#149): merge PRs whose gate labels are green, then
# hand off to the PM for the acceptance close. gh is stubbed via PL_FAKE_PRS so the gate
# decision is exercised deterministically; NO real merge ever happens in tests.
setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  export PL_FAKE_PRS="$(mktemp)"

  # gh stub: serves PR list + per-PR files from PL_FAKE_PRS; logs everything else.
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "pr list")  jq '[.[] | {number, labels}]' "$PL_FAKE_PRS" ;;
  "pr view")  n="$3"; jq --arg n "$n" '.[] | select(.number == ($n|tonumber)) | {files}' "$PL_FAKE_PRS" ;;
  "repo view") echo "acme/persona-lab" ;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
}

teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_FAKE_PRS" "$(dirname "$PL_RUNS_DIR")"; }

fake_prs() { printf '%s' "$1" > "$PL_FAKE_PRS"; }

# ── Merge when the gates are green ───────────────────────────────────────────────────────

@test "integrate: merges a PR with eng+qa approvals that touches scripts/" {
  fake_prs '[
    {"number":197,"labels":[{"name":"gate:eng-approved"},{"name":"gate:qa-approved"}],"files":[{"path":"scripts/dispatch.sh"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  grep -qE "pr merge.*197.*--squash" "$PL_GH_LOG"
  # gated-autonomous merge: never --admin, never force
  if grep -qE "pr merge.*--admin" "$PL_GH_LOG"; then false; fi
}

@test "integrate: does NOT merge a PR missing gate:eng-approved" {
  fake_prs '[
    {"number":200,"labels":[{"name":"gate:qa-approved"}],"files":[{"path":"scripts/x.sh"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  if grep -qE "pr merge" "$PL_GH_LOG"; then false; fi
}

@test "integrate: a gate:changes-requested label BLOCKS merge even with approvals present" {
  fake_prs '[
    {"number":201,"labels":[{"name":"gate:eng-approved"},{"name":"gate:qa-approved"},{"name":"gate:changes-requested"}],"files":[{"path":"scripts/x.sh"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  if grep -qE "pr merge" "$PL_GH_LOG"; then false; fi
}

# ── QA gate is conditional on what the diff touches ───────────────────────────────────────

@test "integrate: a docs-only PR merges with eng approval alone (QA not required)" {
  fake_prs '[
    {"number":202,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"docs/readme.md"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  grep -qE "pr merge.*202.*--squash" "$PL_GH_LOG"
}

@test "integrate: a PR touching scripts/ WITHOUT gate:qa-approved is NOT merged" {
  fake_prs '[
    {"number":203,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"scripts/x.sh"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  if grep -qE "pr merge" "$PL_GH_LOG"; then false; fi
}

@test "integrate: a PR touching tests/ WITHOUT gate:qa-approved is NOT merged" {
  fake_prs '[
    {"number":204,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"tests/x.bats"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  if grep -qE "pr merge" "$PL_GH_LOG"; then false; fi
}

# ── Safety: checkpoint, no self-close, dry-run ────────────────────────────────────────────

@test "integrate: labels the merged PR state:merged and NEVER closes the issue itself" {
  fake_prs '[
    {"number":205,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"docs/x.md"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  grep -qE "pr merge.*205" "$PL_GH_LOG"
  # PM acceptance close is a SEPARATE step (ADR-0001) — the pipeline must never close.
  if grep -qE "issue close" "$PL_GH_LOG"; then false; fi
  grep -qE "state:merged" "$PL_GH_LOG"
}

@test "integrate: --dry-run reports the merge target but invokes no merge" {
  fake_prs '[
    {"number":206,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"docs/x.md"}]}
  ]'
  run scripts/integrate.sh --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "206"
  if grep -qE "pr merge" "$PL_GH_LOG"; then false; fi
}

@test "integrate: checkpoints the pre-merge SHA before a destructive merge" {
  fake_prs '[
    {"number":210,"labels":[{"name":"gate:eng-approved"},{"name":"gate:qa-approved"}],"files":[{"path":"scripts/x.sh"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  grep -qE "pr merge.*210" "$PL_GH_LOG"
  # founder decision: checkpoint-before-destructive — a checkpoint record must be written.
  cat "$PL_RUNS_DIR"/*.ndjson | jq -e 'select(.outcome=="checkpoint" and (.action|test("pre-merge")))' >/dev/null
  # MUTATION PROOF: drop the checkpoint runlog call → no checkpoint record, this fails.
}

@test "integrate: a PR whose file listing fails is NOT merged (fail-safe, can't confirm QA surface)" {
  # gh pr view fails (transient API error). If files come back empty, the QA surface is unknown —
  # the pipeline must NOT merge (a scripts/ or tests/ change could slip past Priya's gate).
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "pr list")  jq '[.[] | {number, labels}]' "$PL_FAKE_PRS" ;;
  "pr view")  exit 1 ;;
  "repo view") echo "acme/persona-lab" ;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
  fake_prs '[
    {"number":299,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"scripts/x.sh"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  if grep -qE "pr merge" "$PL_GH_LOG"; then false; fi
  # MUTATION PROOF: drop the empty-files fail-safe guard → this PR merges, this fails.
}

@test "integrate: in a mixed batch, only the green PR merges" {
  fake_prs '[
    {"number":301,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"docs/a.md"}]},
    {"number":302,"labels":[{"name":"gate:eng-approved"},{"name":"gate:changes-requested"}],"files":[{"path":"docs/b.md"}]},
    {"number":303,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"scripts/c.sh"}]}
  ]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  grep -qE "pr merge.*301" "$PL_GH_LOG"          # docs-only, eng-approved → merges
  if grep -qE "pr merge.*302" "$PL_GH_LOG"; then false; fi   # changes-requested → blocked
  if grep -qE "pr merge.*303" "$PL_GH_LOG"; then false; fi   # scripts/ without qa → blocked
}

@test "integrate: nothing mergeable exits 0 quietly" {
  fake_prs '[]'
  run scripts/integrate.sh
  [ "$status" -eq 0 ]
  if grep -qE "pr merge" "$PL_GH_LOG"; then false; fi
}
