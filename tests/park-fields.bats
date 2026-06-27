setup() {
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  # Minimal gh stub: log all calls, return canned body for issue view
  export PL_GH_LOG="$(mktemp)"
  export PL_ISSUE_BODY_FILE="$(mktemp)"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/42";;
  "issue comment") echo "ok";;
  "issue edit")   echo "ok";;
  "issue view")
    # return canned body from PL_ISSUE_BODY_FILE
    if [ -f "$PL_ISSUE_BODY_FILE" ]; then
      cat "$PL_ISSUE_BODY_FILE"
    fi
    ;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_ISSUE_BODY_FILE"; }

# ---------------------------------------------------------------------------
# park sub-verb: required fields guard
# ---------------------------------------------------------------------------

@test "park: succeeds with all required fields" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner "Tom" \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy the upstream service"
  [ "$status" -eq 0 ]
}

@test "park: embeds pl-fields JSON block in comment" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner "Tom" \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy the upstream service"
  [ "$status" -eq 0 ]
  grep -q "issue comment 42" "$PL_GH_LOG"
  grep -q "pl-fields" "$PL_GH_LOG"
}

@test "park: pl-fields block contains all four required fields" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner "Tom" \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy the upstream service"
  [ "$status" -eq 0 ]
  grep -q "blocker_type" "$PL_GH_LOG"
  grep -q "dependency" "$PL_GH_LOG"
  grep -q '"owner"' "$PL_GH_LOG"
  grep -q '"deadline"' "$PL_GH_LOG"
  grep -q "unblocking_ask" "$PL_GH_LOG"
}

@test "park: adds blocked-by:<type> label" {
  run scripts/queue.sh park 42 \
    --blocker-type coordination \
    --owner "Raj" \
    --deadline "2026-07-15" \
    --unblocking-ask "Confirm schema"
  [ "$status" -eq 0 ]
  grep -q "issue edit 42 --add-label blocked-by:coordination" "$PL_GH_LOG"
}

@test "park: rejects missing --blocker-type" {
  run scripts/queue.sh park 42 \
    --owner "Tom" \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocker"* ]] || [[ "${lines[*]}" == *"blocker"* ]]
}

@test "park: rejects missing --owner" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner"* ]] || [[ "${lines[*]}" == *"owner"* ]]
}

@test "park: rejects missing --deadline" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner "Tom" \
    --unblocking-ask "Deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"deadline"* ]] || [[ "${lines[*]}" == *"deadline"* ]]
}

@test "park: rejects missing --unblocking-ask" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner "Tom" \
    --deadline "2026-07-10"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unblocking"* ]] || [[ "${lines[*]}" == *"unblocking"* ]]
}

@test "park: rejects invalid blocker_type" {
  run scripts/queue.sh park 42 \
    --blocker-type invalid_type \
    --owner "Tom" \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocker_type"* ]] || [[ "${lines[*]}" == *"blocker_type"* ]]
}

@test "park: --repo flag is forwarded to gh" {
  run scripts/queue.sh park 42 --repo o/r \
    --blocker-type dependency \
    --owner "Tom" \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy"
  [ "$status" -eq 0 ]
  grep -q -- "--repo o/r" "$PL_GH_LOG"
}

# ---------------------------------------------------------------------------
# quarantine sub-verb: required fields guard
# ---------------------------------------------------------------------------

@test "quarantine: succeeds with all required fields" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --deadline "2026-07-10" \
    --origin "external:github-issue"
  [ "$status" -eq 0 ]
}

@test "quarantine: embeds pl-fields JSON block in comment" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --deadline "2026-07-10" \
    --origin "external:github-issue"
  [ "$status" -eq 0 ]
  grep -q "issue comment 42" "$PL_GH_LOG"
  grep -q "pl-fields" "$PL_GH_LOG"
}

@test "quarantine: pl-fields block contains all three required fields" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --deadline "2026-07-10" \
    --origin "external:github-issue"
  [ "$status" -eq 0 ]
  grep -q '"owner"' "$PL_GH_LOG"
  grep -q '"deadline"' "$PL_GH_LOG"
  grep -q '"origin"' "$PL_GH_LOG"
  grep -q "external:github-issue" "$PL_GH_LOG"
}

@test "quarantine: adds quarantine label" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --deadline "2026-07-10" \
    --origin "external:github-issue"
  [ "$status" -eq 0 ]
  grep -q "issue edit 42 --add-label quarantine" "$PL_GH_LOG"
}

@test "quarantine: rejects missing --owner" {
  run scripts/queue.sh quarantine 42 \
    --deadline "2026-07-10" \
    --origin "external:github-issue"
  [ "$status" -ne 0 ]
  [[ "$output" == *"owner"* ]] || [[ "${lines[*]}" == *"owner"* ]]
}

@test "quarantine: rejects missing --deadline" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --origin "external:github-issue"
  [ "$status" -ne 0 ]
  [[ "$output" == *"deadline"* ]] || [[ "${lines[*]}" == *"deadline"* ]]
}

@test "quarantine: rejects missing --origin" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --deadline "2026-07-10"
  [ "$status" -ne 0 ]
  [[ "$output" == *"origin"* ]] || [[ "${lines[*]}" == *"origin"* ]]
}

# ---------------------------------------------------------------------------
# resume sub-verb: required blocker_resolution guard
# ---------------------------------------------------------------------------

@test "resume: succeeds with --resolution" {
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh resume 42 \
    --resolution "Upstream service deployed at 14:00Z"
  [ "$status" -eq 0 ]
}

@test "resume: embeds HANDOFF comment with resolution" {
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh resume 42 \
    --resolution "Upstream service deployed"
  [ "$status" -eq 0 ]
  grep -q "issue comment 42" "$PL_GH_LOG"
  grep -q "Upstream service deployed" "$PL_GH_LOG"
}

@test "resume: removes blocked-by:<type> label (reads blocker_type from pl-fields)" {
  # Stub gh issue view to return a body with a pl-fields block
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh resume 42 \
    --resolution "Blocker cleared"
  [ "$status" -eq 0 ]
  grep -q "issue edit 42 --remove-label blocked-by:dependency" "$PL_GH_LOG"
}

@test "resume: rejects missing --resolution" {
  run scripts/queue.sh resume 42
  [ "$status" -ne 0 ]
  [[ "$output" == *"resolution"* ]] || [[ "${lines[*]}" == *"resolution"* ]]
}

@test "resume: --repo flag is forwarded" {
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh resume 42 --repo o/r \
    --resolution "Cleared"
  [ "$status" -eq 0 ]
  grep -q -- "--repo o/r" "$PL_GH_LOG"
}

# ---------------------------------------------------------------------------
# fields sub-verb: read path — parses pl-fields JSON block from issue body
# ---------------------------------------------------------------------------

@test "fields: extracts pl-fields JSON from issue body" {
  # Write a canned body that contains a pl-fields block
  printf '<!-- pl-fields\n{"owner":"Tom","deadline":"2026-07-10","blocker_type":"dependency","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh fields 42
  [ "$status" -eq 0 ]
  [[ "$output" == *'"owner"'* ]]
  [[ "$output" == *'"Tom"'* ]]
  [[ "$output" == *'"deadline"'* ]]
  [[ "$output" == *'"blocker_type"'* ]]
}

@test "fields: returns exit 1 when no pl-fields block present" {
  printf 'No structured block here\n' > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh fields 42
  [ "$status" -ne 0 ]
  [[ "$output" == *"no pl-fields block"* ]] || [[ "${lines[*]}" == *"pl-fields"* ]]
}

@test "fields: --repo flag is forwarded to gh issue view" {
  printf '<!-- pl-fields\n{"owner":"PM"}\n-->\n' > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh fields 42 --repo o/r
  [ "$status" -eq 0 ]
  grep -q -- "--repo o/r" "$PL_GH_LOG"
}
