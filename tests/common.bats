setup() { source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"; }

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

@test "pl_manifest_get: nested key without yq fails closed (no silent default)" {
  # only meaningful when yq is absent; if yq is present this asserts the yq path returns the value
  export PL_CONFIG_DIR="$(mktemp -d)"
  local mf; mf="$PL_CONFIG_DIR/manifest.yml"
  printf 'engagement:\n  developer:\n    capacity: writes\n' > "$mf"
  run pl_manifest_get engagement.developer.capacity
  rm -rf "$PL_CONFIG_DIR"
  if command -v yq >/dev/null 2>&1; then [ "$status" -eq 0 ] && [ "$output" = "writes" ]; else [ "$status" -ne 0 ]; fi
}
