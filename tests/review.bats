# review.bats — review.sh wraps gh pr review/comment through the W1 envelope.
setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"   # isolate run records
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "pr review")  echo "https://github.com/o/r/pull/7#pullrequestreview-1";;
  "pr comment") echo "https://github.com/o/r/pull/7#issuecomment-1";;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "${PL_RUNS_DIR%/runs}"; }

@test "review: approve event emits gh pr review --approve through the envelope" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type REVIEW \
      --body "LGTM" --event approve
  [ "$status" -eq 0 ]
  grep -q "pr review 7" "$PL_GH_LOG"
  grep -q -- "--approve" "$PL_GH_LOG"
}

@test "review: request-changes event maps to gh pr review --request-changes" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type BLOCKER \
      --body "tests missing" --event request-changes
  [ "$status" -eq 0 ]
  grep -q -- "--request-changes" "$PL_GH_LOG"
}

@test "review: comment event maps to gh pr review --comment" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type REVIEW \
      --body "nit" --event comment
  [ "$status" -eq 0 ]
  grep -q -- "--comment" "$PL_GH_LOG"
}

@test "review: default event (no --event) posts a pr comment, not a review" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type REVIEW --body "fyi"
  [ "$status" -eq 0 ]
  grep -q "pr comment 7" "$PL_GH_LOG"
  if grep -q "pr review" "$PL_GH_LOG"; then false; fi
}

@test "review: body carries the W1 envelope (avatar img + badge + AI · role)" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type REVIEW \
      --body "ship it" --event approve
  [ "$status" -eq 0 ]
  grep -q 'align="left"' "$PL_GH_LOG"          # float avatar header
  grep -q "shields.io/badge" "$PL_GH_LOG"      # record type badge
  grep -qF 'avatars/priya/priya-64.png' "$PL_GH_LOG"  # persona avatar
  grep -qF 'AI` · Head of QA' "$PL_GH_LOG"     # AI · role line
}

@test "review: envelope has no <br clear> and no robot emoji (spec)" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type REVIEW \
      --body "ok" --event approve
  [ "$status" -eq 0 ]
  if grep -q "br clear" "$PL_GH_LOG"; then false; fi
  if grep -q "🤖" "$PL_GH_LOG"; then false; fi
}

@test "review: writes a run record (record_type bus, action bus:review, issue_number=pr)" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type REVIEW \
      --body "ok" --event approve
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS_DIR" -name '*.ndjson' | head -1)"
  [ -n "$ndjson_file" ]
  record="$(tail -1 "$ndjson_file")"
  echo "$record" | jq -e '.record_type == "bus"'
  echo "$record" | jq -e '.action == "bus:review"'
  echo "$record" | jq -e '.persona == "Priya"'
  echo "$record" | jq -e '.issue_number == 7'
}

@test "review: --repo targets the named repo" {
  run scripts/review.sh 7 --repo o/r --persona Priya --tier "T · Head of QA" --type REVIEW \
      --body "ok" --event approve
  [ "$status" -eq 0 ]
  grep -q -- "--repo o/r" "$PL_GH_LOG"
}

@test "review: rejects an unknown --event value" {
  run scripts/review.sh 7 --persona Priya --tier "T · Head of QA" --type REVIEW \
      --body "ok" --event bogus
  [ "$status" -ne 0 ]
}
