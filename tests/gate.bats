setup() {
  export PL_WORK="$(mktemp -d)"; cd "$PL_WORK"; git init -q
  git config user.email t@t; git config user.name t
  mkdir -p .claude/persona-lab; echo '{"max_lines":400,"max_files":20}' > .claude/persona-lab/diff_budget.json
}

teardown() { rm -rf "$PL_WORK"; }

@test "gate: passes when manifest ran, diff within budget, and a REVIEW cites HEAD" {
  echo a > f.txt; git add f.txt; git commit -qm x; head="$(git rev-parse HEAD)"
  : > .claude/persona-lab/verified.marker
  echo "{\"commit_sha\":\"$head\",\"verdict\":\"approved\"}" > .claude/persona-lab/review.json
  run "$BATS_TEST_DIRNAME/../scripts/gate.sh" check --head "$head"
  [ "$status" -eq 0 ]
}

@test "gate: fails when the REVIEW cites a stale commit (HEAD moved)" {
  echo a > f.txt; git add f.txt; git commit -qm x
  : > .claude/persona-lab/verified.marker
  echo '{"commit_sha":"deadbeef","verdict":"approved"}' > .claude/persona-lab/review.json
  echo b >> f.txt; git commit -aqm y; head="$(git rev-parse HEAD)"
  run "$BATS_TEST_DIRNAME/../scripts/gate.sh" check --head "$head"
  [ "$status" -ne 0 ]
}

@test "gate: fails when no verification marker exists (self-close blocked)" {
  echo a > f.txt; git add f.txt; git commit -qm x; head="$(git rev-parse HEAD)"
  echo "{\"commit_sha\":\"$head\",\"verdict\":\"approved\"}" > .claude/persona-lab/review.json
  run "$BATS_TEST_DIRNAME/../scripts/gate.sh" check --head "$head"
  [ "$status" -ne 0 ]
}

@test "gate: fails when diff exceeds the line budget" {
  # Create a base commit so HEAD~1 exists
  printf 'x\n%.0s' 1 2 3 4 5 6 7 8 9 10 > f.txt; git add f.txt; git commit -qm base
  # Add >400 lines in a second commit so HEAD~1 diff is large
  python3 -c "print('line\n' * 500)" > f.txt; git commit -aqm big
  head="$(git rev-parse HEAD)"
  : > .claude/persona-lab/verified.marker
  echo "{\"commit_sha\":\"$head\",\"verdict\":\"approved\"}" > .claude/persona-lab/review.json
  run "$BATS_TEST_DIRNAME/../scripts/gate.sh" check --head "$head"
  [ "$status" -ne 0 ]
}

@test "gate: fails when there is no REVIEW record" {
  echo a > f.txt; git add f.txt; git commit -qm x; head="$(git rev-parse HEAD)"
  : > .claude/persona-lab/verified.marker
  run "$BATS_TEST_DIRNAME/../scripts/gate.sh" check --head "$head"
  [ "$status" -ne 0 ]
}

@test "gate: fails when the REVIEW verdict is not approved" {
  echo a > f.txt; git add f.txt; git commit -qm x; head="$(git rev-parse HEAD)"
  : > .claude/persona-lab/verified.marker
  echo "{\"commit_sha\":\"$head\",\"verdict\":\"changes-requested\"}" > .claude/persona-lab/review.json
  run "$BATS_TEST_DIRNAME/../scripts/gate.sh" check --head "$head"
  [ "$status" -ne 0 ]
}
