@test "schemas: each package schema declares required fields and is valid JSON" {
  for s in "${BATS_TEST_DIRNAME}/../config/schemas/"*.json; do
    jq -e '.required | type=="array" and length>0' "$s"
  done
}

@test "schemas: REVIEW verdict enum is the canonical three" {
  run jq -r '.properties.verdict.enum | join(",")' "${BATS_TEST_DIRNAME}/../config/schemas/review.json"
  [ "$output" = "approved,changes-requested,bounce:out-of-scope" ]
}

# --- run-record conformance ---

@test "schemas: validate-run-record rejects a malformed record (missing required fields)" {
  run "${BATS_TEST_DIRNAME}/../scripts/validate-run-record.sh" \
    '{"ts":"2024-01-01T00:00:00Z","persona":"Ben"}'
  [ "$status" -ne 0 ]
}

@test "schemas: validate-run-record accepts a well-formed record produced by runlog.sh" {
  export PL_RUNS="$(mktemp -d)/runs"
  scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome acted --tokens 42
  record="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  run "${BATS_TEST_DIRNAME}/../scripts/validate-run-record.sh" "$record"
  [ "$status" -eq 0 ]
}

@test "schemas: validate-run-record rejects a record with wrong type (ts is number, not string)" {
  run "${BATS_TEST_DIRNAME}/../scripts/validate-run-record.sh" \
    '{"ts":12345,"persona":"Ben","repo":"finances","trigger":"summon","outcome":"acted"}'
  [ "$status" -ne 0 ]
}
