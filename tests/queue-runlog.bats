# queue-runlog.bats — verifies that queue.sh bus operations append run records
setup() {
  export PL_RUNS="$(mktemp -d)/runs"
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "${PL_GH_LOG:-/dev/null}"
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/42";;
  "issue comment") echo "https://github.com/o/r/issues/42#issuecomment-1";;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
  export PL_GH_LOG="$(mktemp)"
}
teardown() { rm -rf "$PL_TEST_BIN" "${PL_GH_LOG:-}" "${PL_RUNS%/runs}"; }

@test "queue comment: appends a bus run record" {
  run scripts/queue.sh comment 42 --persona Doug --tier "T · Developer" --type HANDOFF --body "done"
  [ "$status" -eq 0 ]
  # A run record file must exist
  ndjson_file="$(find "$PL_RUNS" -name '*.ndjson' | head -1)"
  [ -n "$ndjson_file" ]
  record="$(tail -1 "$ndjson_file")"
  echo "$record" | jq -e '.record_type == "bus"'
  echo "$record" | jq -e '.action == "bus:comment"'
  echo "$record" | jq -e '.persona == "Doug"'
}

@test "queue comment: bus record includes issue_number" {
  run scripts/queue.sh comment 55 --persona Tom --tier "T · Architect" --type HANDOFF --body "spec done"
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS" -name '*.ndjson' | head -1)"
  record="$(tail -1 "$ndjson_file")"
  echo "$record" | jq -e '.issue_number == 55'
}

@test "queue park: appends a bus run record" {
  run scripts/queue.sh park 77 \
    --blocker-type decision --owner Chris --deadline 2099-01-01 \
    --unblocking-ask "approve the approach"
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS" -name '*.ndjson' | head -1)"
  [ -n "$ndjson_file" ]
  record="$(tail -1 "$ndjson_file")"
  echo "$record" | jq -e '.record_type == "bus"'
  echo "$record" | jq -e '.action == "bus:park"'
}

@test "queue quarantine: appends a bus run record" {
  run scripts/queue.sh quarantine 88 \
    --owner Chris --deadline 2099-01-01 --origin "stray-issue"
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS" -name '*.ndjson' | head -1)"
  [ -n "$ndjson_file" ]
  record="$(tail -1 "$ndjson_file")"
  echo "$record" | jq -e '.record_type == "bus"'
  echo "$record" | jq -e '.action == "bus:quarantine"'
}

@test "queue comment bus record passes validate-run-record" {
  run scripts/queue.sh comment 42 --persona Doug --tier "T · Developer" --type HANDOFF --body "done"
  [ "$status" -eq 0 ]
  ndjson_file="$(find "$PL_RUNS" -name '*.ndjson' | head -1)"
  record="$(tail -1 "$ndjson_file")"
  run scripts/validate-run-record.sh "$record"
  [ "$status" -eq 0 ]
}
