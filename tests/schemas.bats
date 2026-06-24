@test "schemas: each package schema declares required fields and is valid JSON" {
  for s in "${BATS_TEST_DIRNAME}/../config/schemas/"*.json; do
    jq -e '.required | type=="array" and length>0' "$s"
  done
}

@test "schemas: REVIEW verdict enum is the canonical three" {
  run jq -r '.properties.verdict.enum | join(",")' "${BATS_TEST_DIRNAME}/../config/schemas/review.json"
  [ "$output" = "approved,changes-requested,bounce:out-of-scope" ]
}
