setup() { export PL_RUNS="$(mktemp -d)/runs"; }
@test "runlog: appends a valid NDJSON record with persona+repo+outcome" {
  run scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome acted --tokens 1200
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.persona=="Ben" and .repo=="finances" and .outcome=="acted"'
}
