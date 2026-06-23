setup() { source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"; }

@test "pl_repo_root returns the git toplevel" {
  run pl_repo_root
  [ "$status" -eq 0 ]
  [ -d "$output" ]
}
