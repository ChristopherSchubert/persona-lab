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
