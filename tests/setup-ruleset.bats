@test "setup-ruleset --dry-run: emits valid JSON targeting persona-lock/*" {
  run scripts/setup-ruleset.sh --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.target=="branch"'
  echo "$output" | jq -e '.conditions.ref_name.include[0]=="refs/heads/persona-lock/**"'
  echo "$output" | jq -e '.rules | map(.type) | contains(["deletion","non_fast_forward"])'
}
@test "setup-ruleset (no args): defaults to dry-run JSON" {
  run scripts/setup-ruleset.sh
  [ "$status" -eq 0 ]; echo "$output" | jq -e '.name=="persona-lab-lock"'
}
@test "setup-ruleset --apply: refuses without the App id (deferred), does not POST" {
  run bash -c 'echo y | scripts/setup-ruleset.sh --apply'
  [ "$status" -ne 0 ]
}
