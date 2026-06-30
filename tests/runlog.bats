setup() { export PL_RUNS="$(mktemp -d)/runs"; }

@test "runlog: honors PL_RUNS_DIR override (test isolation)" {
  dir="$(mktemp -d)/isolated"
  run env PL_RUNS_DIR="$dir" PL_RUNS="" scripts/runlog.sh append \
    --persona Ben --repo finances --trigger summon --outcome acted
  [ "$status" -eq 0 ]
  line="$(tail -1 "$dir/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.persona == "Ben"'
}

@test "runlog: PL_RUNS_DIR takes precedence over PL_RUNS" {
  win="$(mktemp -d)/win"; lose="$(mktemp -d)/lose"
  run env PL_RUNS_DIR="$win" PL_RUNS="$lose" scripts/runlog.sh append \
    --persona Ben --repo finances --trigger summon --outcome acted
  [ "$status" -eq 0 ]
  [ -f "$win/$(date -u +%F).ndjson" ]
  if [ -f "$lose/$(date -u +%F).ndjson" ]; then false; fi
}

@test "runlog: appends a valid NDJSON record with persona+repo+outcome" {
  run scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome acted --tokens 1200
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.persona=="Ben" and .repo=="finances" and .outcome=="acted"'
}

@test "runlog: --role flag writes role field" {
  run scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome acted \
    --role developer
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.role == "developer"'
}

@test "runlog: --action flag writes action field" {
  run scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome acted \
    --action "bus:comment"
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.action == "bus:comment"'
}

@test "runlog: --record-type flag writes record_type field" {
  run scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome acted \
    --record-type bus
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.record_type == "bus"'
}

@test "runlog: --artifact-url flag writes artifact_url field" {
  run scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome acted \
    --artifact-url "https://github.com/o/r/issues/42"
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.artifact_url == "https://github.com/o/r/issues/42"'
}

@test "runlog: --parent-id flag writes parent_id field" {
  run scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome acted \
    --parent-id "run-20240101T000000Z"
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.parent_id == "run-20240101T000000Z"'
}

@test "runlog: --issue-number flag writes issue_number field" {
  run scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome acted \
    --issue-number 42
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.issue_number == 42'
}

@test "runlog: omitted optional fields are absent from record (lean record)" {
  run scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome acted
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  # none of the new optional fields should appear
  echo "$line" | jq -e 'has("role") | not'
  echo "$line" | jq -e 'has("action") | not'
  echo "$line" | jq -e 'has("record_type") | not'
  echo "$line" | jq -e 'has("artifact_url") | not'
  echo "$line" | jq -e 'has("parent_id") | not'
  echo "$line" | jq -e 'has("issue_number") | not'
}

@test "runlog: all new optional fields pass validate-run-record" {
  run scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome acted \
    --role developer --action "bus:comment" --record-type bus \
    --artifact-url "https://github.com/o/r/issues/42" --parent-id "p1" --issue-number 42
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  run scripts/validate-run-record.sh "$line"
  [ "$status" -eq 0 ]
}

# --- --id / update path (issue #7) ---

@test "runlog: append prints a run_id on stdout" {
  run scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome pending
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^run- ]]
}

@test "runlog: append writes run_id field to the NDJSON record" {
  run scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome pending
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.run_id | type == "string"'
}

@test "runlog: update --id patches outcome and cost_tokens in place" {
  run_id="$(scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome pending)"
  run scripts/runlog.sh update --id "$run_id" --outcome acted --tokens 1200
  [ "$status" -eq 0 ]
  line="$(grep "\"$run_id\"" "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.outcome == "acted" and .cost_tokens == 1200'
}

@test "runlog: update --id keeps exactly one record for that run_id" {
  run_id="$(scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome pending)"
  scripts/runlog.sh update --id "$run_id" --outcome acted --tokens 1200
  count="$(grep -c "\"$run_id\"" "$PL_RUNS/$(date -u +%F).ndjson")"
  [ "$count" -eq 1 ]
}

@test "runlog: update --id preserves all original fields" {
  run_id="$(scripts/runlog.sh append --persona Doug --repo persona-lab --trigger summon --outcome pending \
    --role developer --issue-number 42)"
  scripts/runlog.sh update --id "$run_id" --outcome dispatched --tokens 5000
  line="$(grep "\"$run_id\"" "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.persona == "Doug" and .repo == "persona-lab" and .role == "developer" and .issue_number == 42'
}

@test "runlog: update --id on nonexistent id exits non-zero" {
  run scripts/runlog.sh update --id "run-00000000T000000Z-zzzzzzzz" --outcome acted
  [ "$status" -ne 0 ]
}

@test "runlog: update --id with artifact-url merges into record" {
  run_id="$(scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome pending)"
  scripts/runlog.sh update --id "$run_id" --outcome dispatched --artifact-url "https://github.com/o/r/issues/7"
  line="$(grep "\"$run_id\"" "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.artifact_url == "https://github.com/o/r/issues/7"'
}

@test "runlog: updated record passes validate-run-record" {
  run_id="$(scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome pending)"
  scripts/runlog.sh update --id "$run_id" --outcome acted --tokens 800
  line="$(grep "\"$run_id\"" "$PL_RUNS/$(date -u +%F).ndjson")"
  run scripts/validate-run-record.sh "$line"
  [ "$status" -eq 0 ]
}

@test "runlog: update --id finds record in an older-dated file (cross-date lookup)" {
  # Simulate a record written to a "yesterday" file by writing directly.
  mkdir -p "$PL_RUNS"
  yesterday_file="$PL_RUNS/2020-01-01.ndjson"
  old_id="run-20200101T000000Z-deadbeef"
  printf '{"run_id":"%s","ts":"2020-01-01T00:00:00Z","persona":"Ben","repo":"finances","trigger":"summon","outcome":"pending","cost_tokens":0}\n' \
    "$old_id" > "$yesterday_file"

  scripts/runlog.sh update --id "$old_id" --outcome acted --tokens 42
  line="$(grep "\"$old_id\"" "$yesterday_file")"
  echo "$line" | jq -e '.outcome == "acted"'
  echo "$line" | jq -e '.cost_tokens == 42'
  # MUTATION PROOF: remove the multi-file search loop → update exits non-zero, this fails.
}
