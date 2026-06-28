@test "assign-names: every role returns its one fixed name, repo-independent" {
  run scripts/assign-names.sh developer finances
  [ "$status" -eq 0 ]; [ -n "$output" ]
  grep -F "$output" docs/personas/_name-pools.md   # the name appears in the roster
  # same across repos — one person per role, no per-repo pools
  [ "$(scripts/assign-names.sh developer finances)" = "$(scripts/assign-names.sh developer schubert)" ]
}
@test "assign-names: platform and repo roles all resolve to their fixed name" {
  [ "$(scripts/assign-names.sh product-manager anyrepo)" = "Sarah" ]
  [ "$(scripts/assign-names.sh finops other)" = "Dave" ]
  [ "$(scripts/assign-names.sh developer anyrepo)" = "Doug" ]
  [ "$(scripts/assign-names.sh qa-analyst anyrepo)" = "Pavel" ]
  [ "$(scripts/assign-names.sh technical-writer anyrepo)" = "Morgan" ]
  [ "$(scripts/assign-names.sh delivery-manager anyrepo)" = "Remy" ]
}
@test "assign-names: roster-expansion personas resolve to their fixed names" {
  [ "$(scripts/assign-names.sh reliability-engineer anyrepo)" = "Kai" ]
  [ "$(scripts/assign-names.sh accessibility-analyst anyrepo)" = "Nadia" ]
  [ "$(scripts/assign-names.sh privacy-analyst anyrepo)" = "Vera" ]
}
@test "assign-names: unknown persona fails" {
  run scripts/assign-names.sh bogus finances; [ "$status" -ne 0 ]
}
