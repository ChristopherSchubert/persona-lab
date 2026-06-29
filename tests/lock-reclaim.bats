#!/usr/bin/env bats
# Tests for the lock recovery primitives: inspect / list / checkpoint / reclaim.
# Uses the stateful Git-Data stub at tests/stubs/gh (state in $PL_GH_STATE).

setup() {
  export PL_GH_STATE="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}
teardown() { rm -rf "$PL_GH_STATE"; }

@test "inspect: free lock reports {}" {
  run scripts/lock.sh inspect --repo finances
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "inspect: held lock reports holder, claimed_at and fence" {
  fence="$(scripts/lock.sh claim --repo finances --holder Doug)"
  run scripts/lock.sh inspect --repo finances
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .holder)" = "Doug" ]
  [ "$(echo "$output" | jq -r .fence)" = "$fence" ]
  [ -n "$(echo "$output" | jq -r .claimed_at)" ]
}

@test "list: enumerates persona-lock/<repo> refs, not the archive namespace" {
  scripts/lock.sh claim --repo finances --holder Doug >/dev/null
  scripts/lock.sh claim --repo billing  --holder Doug >/dev/null
  scripts/lock.sh checkpoint --repo finances >/dev/null   # creates an archive ref
  run scripts/lock.sh list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^finances	'
  echo "$output" | grep -q '^billing	'
  # archive refs must NOT appear in the live-lock listing
  if echo "$output" | grep -q 'archive'; then false; fi
}

@test "checkpoint: preserves the lock commit under the archive namespace (no delete)" {
  fence="$(scripts/lock.sh claim --repo finances --holder Doug)"
  run scripts/lock.sh checkpoint --repo finances
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "persona-lock-archive/finances/$fence"
  # the original lock is still held — checkpoint does not release
  [ "$(scripts/lock.sh status --repo finances)" = "held" ]
}

@test "reclaim: delete + recreate yields a NEW fence and never forces" {
  old="$(scripts/lock.sh claim --repo finances --holder Doug)"
  run scripts/lock.sh reclaim --repo finances
  [ "$status" -eq 0 ]                 # would be 3 if the stub saw a force/PATCH
  new="$output"
  [ -n "$new" ]
  [ "$new" != "$old" ]
  [ "$(scripts/lock.sh status --repo finances)" = "held" ]
}

@test "reclaim: a free lock is a no-op" {
  run scripts/lock.sh reclaim --repo finances
  [ "$status" -eq 0 ]
  [ "$output" = "free" ]
}

@test "recovery path contains no force / PATCH command invocation" {
  # belt-and-suspenders alongside the stub's runtime refusal
  run bash -c "grep -nE -- '-X PATCH|force=true|-f force' scripts/lock.sh scripts/watchdog.sh"
  [ "$status" -ne 0 ]   # grep finds nothing
}
