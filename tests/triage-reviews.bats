# triage-reviews.bats — the REVIEW pass (#215): dispatch gate reviewer(s) DIRECTLY against each open
# PR and post the verdict as a COMMENT + gate label ON THE PR. It must NEVER create a tracking issue
# (bus-hygiene #196). gh + claude are stubbed; no real model call, comment, or issue.
setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  export PL_FAKE_PRS="$(mktemp)"
  export PL_FAKE_VERDICT="approve"   # what the stubbed reviewer returns; override per test

  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "pr list")  jq '[.[] | {number, labels}]' "$PL_FAKE_PRS" ;;
  "pr view")  n="$3"; jq --arg n "$n" '.[] | select(.number==($n|tonumber)) | {files}' "$PL_FAKE_PRS" ;;
  "pr diff")  echo "diff --git a/x b/x" ;;
  "repo view") echo "acme/persona-lab" ;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
  export PL_REPO="persona-lab"

  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_GH_LOG"
printf '{"result":"{\\"record_type\\":\\"REVIEW\\",\\"verdict\\":\\"%s\\",\\"body\\":\\"review body\\"}"}' "${PL_FAKE_VERDICT:-approve}"
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  export PL_CLAUDE="$PL_TEST_BIN/fake-claude"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_FAKE_PRS" "$(dirname "$PL_RUNS_DIR")"; }

fake_prs() { printf '%s' "$1" > "$PL_FAKE_PRS"; }

@test "triage-reviews: dispatches eng review, posts a comment + gate:eng-approved ON THE PR, creates NO issue" {
  fake_prs '[{"number":190,"labels":[],"files":[{"path":"docs/x.md"}]}]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  grep -qE "pr review.*190.*--comment" "$PL_GH_LOG"               # verdict posted ON the PR (comment)
  grep -qE "pr edit.*190.*--add-label gate:eng-approved" "$PL_GH_LOG"
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi          # the whole point: no proxy issue
}

@test "triage-reviews: adds the QA reviewer when the diff touches scripts/ (eng + qa, both on the PR)" {
  fake_prs '[{"number":190,"labels":[],"files":[{"path":"scripts/dispatch.sh"}]}]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  grep -qE "pr edit.*190.*--add-label gate:eng-approved" "$PL_GH_LOG"
  grep -qE "pr edit.*190.*--add-label gate:qa-approved" "$PL_GH_LOG"
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: dedup — skips a reviewer whose gate label is already present" {
  fake_prs '[{"number":190,"labels":[{"name":"gate:eng-approved"}],"files":[{"path":"docs/x.md"}]}]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  # eng already approved → lead-engineer not re-dispatched (no second eng review/label)
  if grep -qE "pr edit.*190.*--add-label gate:eng-approved" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: a request-changes verdict sets gate:changes-requested (comment on PR, no issue)" {
  fake_prs '[{"number":190,"labels":[],"files":[{"path":"docs/x.md"}]}]'
  PL_FAKE_VERDICT="request-changes" run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  grep -qE "pr edit.*190.*--add-label gate:changes-requested" "$PL_GH_LOG"
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: a PR with changes-requested is skipped (awaiting the dev)" {
  fake_prs '[{"number":190,"labels":[{"name":"gate:changes-requested"}],"files":[{"path":"docs/x.md"}]}]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "^CLAUDE|pr edit.*190" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: never creates an issue on any path (the core bus-hygiene guarantee)" {
  fake_prs '[
    {"number":190,"labels":[],"files":[{"path":"scripts/a.sh"}]},
    {"number":191,"labels":[],"files":[{"path":"docs/b.md"}]}
  ]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: --dry-run posts nothing and creates nothing" {
  fake_prs '[{"number":190,"labels":[],"files":[{"path":"docs/x.md"}]}]'
  run scripts/triage-reviews.sh --dry-run
  [ "$status" -eq 0 ]
  if grep -qE "pr review|pr edit.*gate:|issue create|^CLAUDE" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: no open PRs exits 0 quietly" {
  fake_prs '[]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "^CLAUDE|pr review|issue create" "$PL_GH_LOG"; then false; fi
}
