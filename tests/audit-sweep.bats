# audit-sweep.bats — proactive discovery: send audit roles to "go hunt for work" and file the
# new findings (dedup'd). gh + claude are stubbed; NO real model/network call is made.
setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  export PL_CLAUDE_LOG="$(mktemp)"
  export PL_FAKE_ISSUES="$(mktemp)"; printf '[]' > "$PL_FAKE_ISSUES"   # no existing open issues
  export PL_REPO="persona-lab"

  # gh stub: `issue list --json …` echoes PL_FAKE_ISSUES; `issue create` prints a URL; rest logged.
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "issue list")   cat "$PL_FAKE_ISSUES";;
  "issue create") echo "https://github.com/o/r/issues/123";;
  "repo view")    echo "acme/persona-lab";;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"

  # claude stub (PL_CLAUDE): emits the --output-format json envelope; .result is a findings array.
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"[{\\"title\\":\\"Doc drift in README\\",\\"body\\":\\"README stale at docs/x.md:4\\",\\"record_type\\":\\"ASSESSMENT\\",\\"priority\\":\\"p2\\"}]"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  export PL_CLAUDE="$PL_TEST_BIN/fake-claude"
}
teardown() {
  rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_CLAUDE_LOG" "$PL_FAKE_ISSUES" "${PL_RUNS_DIR%/runs}"
}

@test "audit-sweep: --dry-run with no args lists every role in the roles file, invokes nothing" {
  printf 'technical-writer\nsecurity-analyst\n' > "$PL_TEST_BIN/roles.txt"
  PL_AUDIT_ROLES="$PL_TEST_BIN/roles.txt" run scripts/audit-sweep.sh --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "technical-writer"
  echo "$output" | grep -qF "security-analyst"
  if grep -q "CLAUDE" "$PL_CLAUDE_LOG"; then false; fi
}

@test "audit-sweep: --dry-run for a single role lists just that role" {
  run scripts/audit-sweep.sh technical-writer --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "technical-writer"
  if grep -q "CLAUDE" "$PL_CLAUDE_LOG"; then false; fi
}

@test "audit-sweep: files a NEW finding as an issue under the discoverer's envelope" {
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  # the harness filed it via queue.sh file -> gh issue create
  grep -qF "issue create" "$PL_GH_LOG"
  grep -qF "Doc drift in README" "$PL_GH_LOG"
  # envelope rendered with the discoverer's resolved NAME (assign-names), not the slug
  tw_name="$(scripts/assign-names.sh technical-writer)"
  grep -qF "$tw_name" "$PL_GH_LOG"
  if grep -qF "persona:technical-writer" "$PL_GH_LOG"; then false; fi   # filed UNROUTED — routing is triage's job
  # priority label applied
  grep -qF "priority:p2" "$PL_GH_LOG"
  # MUTATION PROOF: drop the queue.sh file call → "issue create" absent, this fails.
}

@test "audit-sweep: a finding whose title already exists is skipped (dedup, no refile)" {
  printf '[{"title":"Doc drift in README"}]' > "$PL_FAKE_ISSUES"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  if grep -qF "issue create" "$PL_GH_LOG"; then false; fi
  # MUTATION PROOF: remove the existing-title dedup check → "issue create" appears, this fails.
}

@test "audit-sweep: an empty findings array files nothing" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"[]"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  grep -q "CLAUDE" "$PL_CLAUDE_LOG"
  if grep -qF "issue create" "$PL_GH_LOG"; then false; fi
}

@test "audit-sweep: an invalid finding (no title/body) is not filed" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"[{\\"record_type\\":\\"ASSESSMENT\\"}]"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  if grep -qF "issue create" "$PL_GH_LOG"; then false; fi
}

@test "audit-sweep: writes a run record (trigger=audit-sweep) for the swept role" {
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS_DIR" -name '*.ndjson' | head -1)"
  [ -n "$ndjson_file" ]
  grep -qF '"trigger":"audit-sweep"' "$ndjson_file"
  grep -qF '"persona":"technical-writer"' "$ndjson_file"
}

@test "audit-sweep: rejects an unknown single role" {
  run scripts/audit-sweep.sh not-a-real-persona
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiF "no agent file"
}

@test "audit-sweep: never calls the real claude binary (uses PL_CLAUDE indirection)" {
  cat > "$PL_TEST_BIN/claude" <<'SH'
#!/usr/bin/env bash
echo "REAL CLAUDE CALLED" >> "$PL_CLAUDE_LOG"
exit 99
SH
  chmod +x "$PL_TEST_BIN/claude"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  if grep -q "REAL CLAUDE CALLED" "$PL_CLAUDE_LOG"; then false; fi
}

# ── Chatty mode + robust parsing (operability) ────────────────────────────────────────

@test "audit-sweep: extracts findings even when the model wraps them in prose" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"Sure! Here is what I found:\\n[{\\"title\\":\\"Prose-wrapped finding\\",\\"body\\":\\"b\\",\\"record_type\\":\\"ASSESSMENT\\",\\"priority\\":\\"p3\\"}]\\nLet me know if you want more."}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  grep -qF "issue create" "$PL_GH_LOG"
  grep -qF "Prose-wrapped finding" "$PL_GH_LOG"
  # MUTATION PROOF: drop the perl bracket-extraction fallback → prose-wrapped array unparsed, this fails.
}

@test "audit-sweep: PL_STREAM streams the turn live AND still files findings" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"docs/x.md"}}]}}'
printf '%s\n' '{"type":"result","subtype":"success","result":"[{\"title\":\"Streamed finding\",\"body\":\"b\",\"record_type\":\"ASSESSMENT\",\"priority\":\"p3\"}]"}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  PL_STREAM=1 run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "Read docs/x.md"      # live tool progress surfaced to the terminal
  grep -qF "issue create" "$PL_GH_LOG"
  grep -qF "Streamed finding" "$PL_GH_LOG"
  # MUTATION PROOF: ignore PL_STREAM (always buffered) → no live "Read docs/x.md" line, this fails.
}

@test "audit-sweep: resolves a gh-valid OWNER/REPO for filing (not the short manifest name)" {
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  grep -qF "issue create" "$PL_GH_LOG"
  grep -qF "acme/persona-lab" "$PL_GH_LOG"   # used the resolved OWNER/REPO via pl_gh_repo
  # MUTATION PROOF: pass the short manifest 'repo' to gh --repo → "acme/persona-lab" absent, this fails.
}

@test "audit-sweep: surfaces the queue.sh error when filing fails (no silent swallow)" {
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "issue list")   cat "$PL_FAKE_ISSUES";;
  "repo view")    echo "acme/persona-lab";;
  "issue create") echo "gh: HTTP 422 validation failed" >&2; exit 1;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "FILE FAILED"
  echo "$output" | grep -qF "422 validation failed"   # the real error is surfaced, not swallowed
  # MUTATION PROOF: redirect the file call's stderr to /dev/null again → error not shown, this fails.
}

@test "audit-sweep: dumps the raw output when it cannot parse a findings array" {
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_CLAUDE_LOG"
printf '{"result":"I reviewed the docs and everything looks fine, no issues to report."}'
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "raw output below"
  echo "$output" | grep -qF "everything looks fine"   # the actual model text is surfaced for debugging
  if grep -qF "issue create" "$PL_GH_LOG"; then false; fi
  # MUTATION PROOF: swallow the raw output on parse failure → "raw output below" absent, this fails.
}

@test "audit-sweep: shows the persona the open issues so it can avoid re-filing (#126)" {
  printf '[{"title":"Already tracked thing"}]' > "$PL_FAKE_ISSUES"
  run scripts/audit-sweep.sh technical-writer
  [ "$status" -eq 0 ]
  grep -qF "Already tracked thing" "$PL_CLAUDE_LOG"   # existing open issue surfaced IN the sweep prompt
  # MUTATION PROOF: drop existing_titles from the prompt → the persona never sees it, this fails.
}
