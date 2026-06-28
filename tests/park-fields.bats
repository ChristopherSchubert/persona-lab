setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"   # isolate bus run records from the real runs dir
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  # Minimal gh stub: log all calls.
  # Body vs comments are intentionally separate so the tests can verify
  # that the read path uses --json comments (not the bare issue body).
  #   PL_ISSUE_BODY_FILE     — returned by "gh issue view" WITHOUT --json flag
  #   PL_ISSUE_COMMENTS_FILE — returned by "gh issue view --json comments ..."
  export PL_GH_LOG="$(mktemp)"
  export PL_ISSUE_BODY_FILE="$(mktemp)"
  export PL_ISSUE_COMMENTS_FILE="$(mktemp)"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/42";;
  "issue comment") echo "ok";;
  "issue edit")   echo "ok";;
  "issue view")
    # Distinguish body-only vs comment-fetching calls.
    # Any invocation that passes --json and includes "comments" in the args
    # returns the comments fixture; otherwise returns the bare body fixture.
    if printf '%s\n' "$@" | grep -q -- '--json'; then
      if [ -f "$PL_ISSUE_COMMENTS_FILE" ]; then cat "$PL_ISSUE_COMMENTS_FILE"; fi
    else
      if [ -f "$PL_ISSUE_BODY_FILE" ]; then cat "$PL_ISSUE_BODY_FILE"; fi
    fi
    ;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_ISSUE_BODY_FILE" "$PL_ISSUE_COMMENTS_FILE"; }

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
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'blocker'
}

@test "park: rejects missing --owner" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy"
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'owner'
}

@test "park: rejects missing --deadline" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner "Tom" \
    --unblocking-ask "Deploy"
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'deadline'
}

@test "park: rejects missing --unblocking-ask" {
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner "Tom" \
    --deadline "2026-07-10"
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'unblocking'
}

@test "park: rejects invalid blocker_type" {
  run scripts/queue.sh park 42 \
    --blocker-type invalid_type \
    --owner "Tom" \
    --deadline "2026-07-10" \
    --unblocking-ask "Deploy"
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'blocker_type'
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
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'owner'
}

@test "quarantine: rejects missing --deadline" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --origin "external:github-issue"
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'deadline'
}

@test "quarantine: rejects missing --origin" {
  run scripts/queue.sh quarantine 42 \
    --owner "PM" \
    --deadline "2026-07-10"
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'origin'
}

# ---------------------------------------------------------------------------
# resume sub-verb: required blocker_resolution guard
# ---------------------------------------------------------------------------

@test "resume: succeeds with --resolution" {
  # pl-fields live in a comment, not the issue body — write to the comments fixture
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_COMMENTS_FILE"
  run scripts/queue.sh resume 42 \
    --resolution "Upstream service deployed at 14:00Z"
  [ "$status" -eq 0 ]
}

@test "resume: embeds HANDOFF comment with resolution" {
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_COMMENTS_FILE"
  run scripts/queue.sh resume 42 \
    --resolution "Upstream service deployed"
  [ "$status" -eq 0 ]
  grep -q "issue comment 42" "$PL_GH_LOG"
  grep -q "Upstream service deployed" "$PL_GH_LOG"
}

@test "resume: removes blocked-by:<type> label (reads blocker_type from pl-fields)" {
  # pl-fields are written to a comment by park; read path must use --json comments
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_COMMENTS_FILE"
  run scripts/queue.sh resume 42 \
    --resolution "Blocker cleared"
  [ "$status" -eq 0 ]
  grep -q "issue edit 42 --remove-label blocked-by:dependency" "$PL_GH_LOG"
}

@test "resume: rejects missing --resolution" {
  run scripts/queue.sh resume 42
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'resolution'
}

@test "resume: --repo flag is forwarded" {
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_COMMENTS_FILE"
  run scripts/queue.sh resume 42 --repo o/r \
    --resolution "Cleared"
  [ "$status" -eq 0 ]
  grep -q -- "--repo o/r" "$PL_GH_LOG"
}

# ---------------------------------------------------------------------------
# fields sub-verb: read path — parses pl-fields JSON block from issue body
# ---------------------------------------------------------------------------

@test "fields: extracts pl-fields JSON from issue comments" {
  # pl-fields are written to comments by park/quarantine; read must use --json comments
  printf '<!-- pl-fields\n{"owner":"Tom","deadline":"2026-07-10","blocker_type":"dependency","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_COMMENTS_FILE"
  run scripts/queue.sh fields 42
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"owner"'
  echo "$output" | grep -qF '"Tom"'
  echo "$output" | grep -qF '"deadline"'
  echo "$output" | grep -qF '"blocker_type"'
}

@test "fields: returns exit 1 when no pl-fields block present" {
  printf 'No structured block here\n' > "$PL_ISSUE_BODY_FILE"
  run scripts/queue.sh fields 42
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'pl-fields'
}

@test "fields: --repo flag is forwarded to gh issue view" {
  printf '<!-- pl-fields\n{"owner":"PM"}\n-->\n' > "$PL_ISSUE_COMMENTS_FILE"
  run scripts/queue.sh fields 42 --repo o/r
  [ "$status" -eq 0 ]
  grep -q -- "--repo o/r" "$PL_GH_LOG"
}

# ---------------------------------------------------------------------------
# Regression — Bug 1: read path must use --json comments, not bare issue body
# ---------------------------------------------------------------------------

@test "fields: fails when pl-fields block is in comments but read uses bare body" {
  # Put pl-fields ONLY in comments fixture (body is empty).
  # If the read path incorrectly uses "gh issue view" without --json comments it
  # will see an empty body and must return a non-zero exit — proving the masking
  # was real and the fix now routes through the correct path.
  : > "$PL_ISSUE_BODY_FILE"   # empty body — no pl-fields here
  printf '<!-- pl-fields\n{"owner":"Tom","blocker_type":"dependency","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_COMMENTS_FILE"
  # Correct implementation reads comments → exit 0 with JSON output.
  run scripts/queue.sh fields 42
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '"owner"'
}

@test "resume: fails when pl-fields block is only in issue body (not comments)" {
  # Put pl-fields ONLY in the body fixture (not comments).
  # A correct implementation reads comments and must fail to find the block here.
  printf '<!-- pl-fields\n{"blocker_type":"dependency","owner":"Tom","deadline":"2026-07-10","unblocking_ask":"Deploy"}\n-->\n' \
    > "$PL_ISSUE_BODY_FILE"
  : > "$PL_ISSUE_COMMENTS_FILE"   # empty comments
  run scripts/queue.sh resume 42 --resolution "Cleared"
  # pl-fields not in comments → must fail (not find the block)
  [ "$status" -ne 0 ]
  { echo "$output"; printf '%s\n' "${lines[@]}"; } | grep -qF 'pl-fields'
}

# ---------------------------------------------------------------------------
# Regression — Bug 2: field values with " or \ must produce valid JSON
# ---------------------------------------------------------------------------

@test "park: field value containing double-quote produces valid JSON" {
  # Use a wrapper script to capture the --body arg passed to "gh issue comment"
  PL_BODY_CAP="$(mktemp)"
  export PL_BODY_CAP
  # Write a capturing stub that replaces the setup stub for this test
  cat > "$PL_TEST_BIN/gh" <<'SH2'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
# Capture the --body value when this is a comment call
if [ "$1 $2" = "issue comment" ]; then
  args=("$@"); i=0
  while [ $i -lt ${#args[@]} ]; do
    if [ "${args[$i]}" = "--body" ]; then
      printf '%s' "${args[$((i+1))]}" > "$PL_BODY_CAP"
      break
    fi
    i=$((i+1))
  done
fi
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/42";;
  "issue comment") echo "ok";;
  "issue edit")   echo "ok";;
  "issue view")
    if printf '%s\n' "$@" | grep -q -- '--json'; then
      if [ -f "$PL_ISSUE_COMMENTS_FILE" ]; then cat "$PL_ISSUE_COMMENTS_FILE"; fi
    else
      if [ -f "$PL_ISSUE_BODY_FILE" ]; then cat "$PL_ISSUE_BODY_FILE"; fi
    fi
    ;;
esac
SH2
  chmod +x "$PL_TEST_BIN/gh"
  run scripts/queue.sh park 42 \
    --blocker-type dependency \
    --owner 'Tom "the architect" Jones' \
    --deadline "2026-07-10" \
    --unblocking-ask 'Deploy the service (uses 8080 by "default")'
  [ "$status" -eq 0 ]
  # Extract the JSON line from the captured comment body
  json_block="$(awk '/^<!-- pl-fields$/{found=1;next} found && /^-->/{exit} found' "$PL_BODY_CAP")"
  # Must be non-empty and parse as valid JSON
  [ -n "$json_block" ]
  printf '%s' "$json_block" | jq -e . > /dev/null
}

@test "quarantine: field value containing double-quote produces valid JSON" {
  PL_BODY_CAP="$(mktemp)"
  export PL_BODY_CAP
  cat > "$PL_TEST_BIN/gh" <<'SH2'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
if [ "$1 $2" = "issue comment" ]; then
  args=("$@"); i=0
  while [ $i -lt ${#args[@]} ]; do
    if [ "${args[$i]}" = "--body" ]; then
      printf '%s' "${args[$((i+1))]}" > "$PL_BODY_CAP"
      break
    fi
    i=$((i+1))
  done
fi
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/42";;
  "issue comment") echo "ok";;
  "issue edit")   echo "ok";;
  "issue view")
    if printf '%s\n' "$@" | grep -q -- '--json'; then
      if [ -f "$PL_ISSUE_COMMENTS_FILE" ]; then cat "$PL_ISSUE_COMMENTS_FILE"; fi
    else
      if [ -f "$PL_ISSUE_BODY_FILE" ]; then cat "$PL_ISSUE_BODY_FILE"; fi
    fi
    ;;
esac
SH2
  chmod +x "$PL_TEST_BIN/gh"
  run scripts/queue.sh quarantine 42 \
    --owner 'PM "lead"' \
    --deadline "2026-07-10" \
    --origin 'external:"jira"'
  [ "$status" -eq 0 ]
  json_block="$(awk '/^<!-- pl-fields$/{found=1;next} found && /^-->/{exit} found' "$PL_BODY_CAP")"
  [ -n "$json_block" ]
  printf '%s' "$json_block" | jq -e . > /dev/null
}
