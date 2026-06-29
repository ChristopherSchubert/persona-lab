# accept.bats — the PM ACCEPTANCE-CLOSE step (#149/#196). For each merged PR labelled state:merged
# that names its issue (Resolves-Issue: #N), Sarah posts an enveloped acceptance citing the merge
# proof, THEN the issue is closed (never a bare close — ADR-0001), and the PR is relabelled
# state:accepted so it is not reprocessed. gh is stubbed; NO real close happens in tests.
setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  export PL_FAKE_PRS="$(mktemp)"

  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "pr list")  jq '[.[] | {number, body}]' "$PL_FAKE_PRS" ;;
  "repo view") echo "acme/persona-lab" ;;
  "issue comment") echo "https://github.com/acme/persona-lab/issues/$3#issuecomment-1" ;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
  export PL_REPO="persona-lab"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_FAKE_PRS" "$(dirname "$PL_RUNS_DIR")"; }

fake_prs() { printf '%s' "$1" > "$PL_FAKE_PRS"; }

@test "accept: posts an enveloped acceptance, THEN closes the issue named in the PR" {
  fake_prs '[
    {"number":197,"body":"Implements review routing.\n\nResolves-Issue: #195"}
  ]'
  run scripts/accept.sh
  [ "$status" -eq 0 ]
  # enveloped acceptance record posted on the issue (not a bare close)
  grep -qE "issue comment.*195" "$PL_GH_LOG"
  # then the issue is closed
  grep -qE "issue close.*195" "$PL_GH_LOG"
  # the acceptance comment is logged BEFORE the close (ADR-0001: proof first)
  [ "$(grep -nE 'issue comment.*195' "$PL_GH_LOG" | head -1 | cut -d: -f1)" -lt \
    "$(grep -nE 'issue close.*195'   "$PL_GH_LOG" | head -1 | cut -d: -f1)" ]
}

@test "accept: relabels the PR state:accepted so it is not reprocessed" {
  fake_prs '[
    {"number":197,"body":"Resolves-Issue: #195"}
  ]'
  run scripts/accept.sh
  [ "$status" -eq 0 ]
  grep -qE "pr edit.*197.*--add-label state:accepted" "$PL_GH_LOG"
  grep -qE "pr edit.*197.*--remove-label state:merged" "$PL_GH_LOG"
}

@test "accept: a merged PR with NO Resolves-Issue trailer is skipped (no close)" {
  fake_prs '[
    {"number":250,"body":"A merge with no issue marker."}
  ]'
  run scripts/accept.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue close" "$PL_GH_LOG"; then false; fi
}

@test "accept: never closes an issue WITHOUT first posting the acceptance record" {
  # If the acceptance comment fails, the issue must NOT be closed (proof-first invariant).
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "pr list")  jq '[.[] | {number, body}]' "$PL_FAKE_PRS" ;;
  "repo view") echo "acme/persona-lab" ;;
  "issue comment") exit 1 ;;   # acceptance post fails
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
  fake_prs '[
    {"number":197,"body":"Resolves-Issue: #195"}
  ]'
  run scripts/accept.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue close" "$PL_GH_LOG"; then false; fi
}

@test "accept: --dry-run names the issue but closes nothing" {
  fake_prs '[
    {"number":197,"body":"Resolves-Issue: #195"}
  ]'
  run scripts/accept.sh --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "195"
  if grep -qE "issue close" "$PL_GH_LOG"; then false; fi
}

@test "accept: nothing to accept exits 0 quietly" {
  fake_prs '[]'
  run scripts/accept.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue close" "$PL_GH_LOG"; then false; fi
}
