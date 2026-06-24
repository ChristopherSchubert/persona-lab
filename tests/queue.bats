setup() {
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in "issue create") echo "https://github.com/o/r/issues/42";; esac
SH
  chmod +x "$PL_TEST_BIN/gh"; export PL_GH_LOG="$(mktemp)"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG"; }

@test "queue file: creates an issue and embeds the AI envelope + record type" {
  run scripts/queue.sh file --persona "Ben" --tier "finances Team · Developer" \
      --type FINDING --title "clock skew 401" --body "details"
  [ "$status" -eq 0 ]
  [[ "$output" == *"issues/42"* ]]
  grep -q "issue create" "$PL_GH_LOG"
  grep -q -- "--body" "$PL_GH_LOG" && grep -q "FINDING" "$PL_GH_LOG"
}

@test "queue comment: appends an enveloped comment to an issue" {
  run scripts/queue.sh comment 42 --persona Ben --tier "finances Team · Developer" --type PROOF --body "fixed"
  [ "$status" -eq 0 ]; grep -q "issue comment 42" "$PL_GH_LOG"
  grep -q "PROOF" "$PL_GH_LOG"
}

@test "queue label: adds a label" {
  run scripts/queue.sh label 42 --add needs-human:decision
  [ "$status" -eq 0 ]; grep -q "issue edit 42 --add-label needs-human:decision" "$PL_GH_LOG"
}

@test "queue close: closes with a state-reason" {
  run scripts/queue.sh close 42 --reason completed
  [ "$status" -eq 0 ]; grep -q "issue close 42" "$PL_GH_LOG"
  grep -q -- "--reason completed" "$PL_GH_LOG"
}

@test "queue query: passes a search and requests json" {
  run scripts/queue.sh query --label needs-human:decision
  [ "$status" -eq 0 ]; grep -q "issue list" "$PL_GH_LOG"
  grep -q -- "--json number,title,labels,state" "$PL_GH_LOG"
}
