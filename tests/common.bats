setup() { source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"; export -f pl_extract_json; }

@test "pl_repo_root returns the git toplevel" {
  run pl_repo_root
  [ "$status" -eq 0 ]
  [ -d "$output" ]
}

@test "pl_manifest_get: reads a top-level scalar via yq or fallback" {
  export PL_CONFIG_DIR="$(mktemp -d)"
  local mf; mf="$PL_CONFIG_DIR/manifest.yml"
  printf 'grain: single\n' > "$mf"
  run pl_manifest_get grain
  rm -rf "$PL_CONFIG_DIR"
  [ "$status" -eq 0 ]; [ "$output" = "single" ]
}

@test "pl_envelope: DELIVERED record renders the green (16a34a) badge" {
  run pl_envelope "Doug" "repo · Developer" DELIVERED "acceptance met"
  [ "$status" -eq 0 ]
  grep -qF "badge/DELIVERED-16a34a" <<<"$output" || false
}

@test "pl_envelope: VERIFICATION is no longer a known record type (falls through to default color)" {
  run pl_envelope "Doug" "repo · Developer" VERIFICATION "x"
  [ "$status" -eq 0 ]
  grep -qF "badge/VERIFICATION-64748b" <<<"$output" || false
}

@test "pl_envelope: FEEDBACK / ASK / REPLY are known record types (non-default color)" {
  run pl_envelope "Doug" "repo · Developer" FEEDBACK "calibration"
  [ "$status" -eq 0 ]
  if grep -q "badge/FEEDBACK-64748b" <<<"$output"; then false; fi
  run pl_envelope "Doug" "repo · Developer" ASK "need input"
  [ "$status" -eq 0 ]
  if grep -q "badge/ASK-64748b" <<<"$output"; then false; fi
  run pl_envelope "Doug" "repo · Developer" REPLY "here you go"
  [ "$status" -eq 0 ]
  if grep -q "badge/REPLY-64748b" <<<"$output"; then false; fi
}

# ── pl_extract_json (issue #153) ───────────────────────────────────────────────────────
# Sarah's predicted edge case: a record/findings array preceded by prose that itself contains
# "[" or "{". The old greedy `(\[.*\]|\{.*\})` grabbed from the FIRST prose bracket through a
# later "]", yielding invalid JSON and silently dropping real work. The fix prefers the fenced
# block, then a balanced-bracket scan that returns the first candidate that actually validates.

@test "pl_extract_json: clean JSON object passes straight through" {
  run bash -c 'printf "%s" "{\"record_type\":\"ASK\",\"body\":\"q\"}" | pl_extract_json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.record_type == "ASK"'
}

@test "pl_extract_json: clean JSON array passes straight through" {
  run bash -c 'printf "%s" "[{\"title\":\"x\"}]" | pl_extract_json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array" and .[0].title == "x"'
}

@test "pl_extract_json: FENCED object after prose containing [brackets] (the #8 DELIVERED drop)" {
  # Doug's DELIVERED for #8 had `[--grace-min N]` in the prose before the fenced object.
  run bash -c 'printf "Done. Added the \`[--grace-min N]\` flag.\n\n\`\`\`json\n{\"record_type\":\"DELIVERED\",\"body\":\"PR #148\"}\n\`\`\`\n" | pl_extract_json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.record_type == "DELIVERED" and (.body | test("148"))'
  # MUTATION PROOF: revert step 2 to `awk "{print}"` (keep prose) → prose leaks in, jq fails,
  # the greedy fallback grabs `[--grace-min N]` → invalid → this drops the record, test fails.
}

@test "pl_extract_json: FENCED array after prose containing **[roster]** (the design-analyst drop)" {
  run bash -c 'printf "Two findings about the \`**[roster]**\` copy.\n\n\`\`\`json\n[{\"title\":\"Badge palette collision\"},{\"title\":\"Zero-state drift\"}]\n\`\`\`\n" | pl_extract_json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array" and length == 2'
}

@test "pl_extract_json: prose-wrapped object with NO fence still parses (regression guard)" {
  run bash -c 'printf "%s" "Here is my reply: {\"record_type\":\"REPLY\",\"body\":\"the convention\"} — hope that helps" | pl_extract_json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.record_type == "REPLY"'
}

@test "pl_extract_json: prose [brackets] + object, NO fence — balanced scan skips the prose bracket" {
  run bash -c 'printf "%s" "Fixed [the flag]. Result: {\"record_type\":\"DELIVERED\",\"body\":\"x\"}" | pl_extract_json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.record_type == "DELIVERED"'
  # MUTATION PROOF: restore the greedy `\[.*\]` first-match → it grabs `[the flag]` (invalid),
  # the record is dropped, this fails.
}

@test "pl_extract_json: prose [brackets] + array, NO fence — returns the real findings array" {
  run bash -c 'printf "%s" "About [roster] copy: [{\"title\":\"a\"},{\"title\":\"b\"}]" | pl_extract_json'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array" and length == 2'
}

@test "pl_extract_json: unparseable prose returns non-zero (no silent garbage)" {
  run bash -c 'printf "%s" "I could not complete this, sorry." | pl_extract_json'
  [ "$status" -ne 0 ]
}

@test "pl_manifest_get: nested key without yq fails closed (no silent default)" {
  # only meaningful when yq is absent; if yq is present this asserts the yq path returns the value
  export PL_CONFIG_DIR="$(mktemp -d)"
  local mf; mf="$PL_CONFIG_DIR/manifest.yml"
  printf 'engagement:\n  developer:\n    capacity: writes\n' > "$mf"
  run pl_manifest_get engagement.developer.capacity
  rm -rf "$PL_CONFIG_DIR"
  if command -v yq >/dev/null 2>&1; then [ "$status" -eq 0 ] && [ "$output" = "writes" ]; else [ "$status" -ne 0 ]; fi
}
