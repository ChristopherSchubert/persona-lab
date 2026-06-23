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
