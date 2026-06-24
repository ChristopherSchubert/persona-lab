@test "assign-names: repo-tier returns a name from that pool, deterministically" {
  run scripts/assign-names.sh developer finances
  [ "$status" -eq 0 ]; [ -n "$output" ]
  grep -F "$output" docs/personas/_name-pools.md   # the name appears in the pool file
  a="$(scripts/assign-names.sh developer finances)"; b="$(scripts/assign-names.sh developer finances)"
  [ "$a" = "$b" ]
}
@test "assign-names: different repos can differ; platform singleton is fixed" {
  [ "$(scripts/assign-names.sh product-manager anyrepo)" = "Sarah" ]
  [ "$(scripts/assign-names.sh head-of-finops other)" = "Dave" ]
}
@test "assign-names: unknown persona fails" {
  run scripts/assign-names.sh bogus finances; [ "$status" -ne 0 ]
}
