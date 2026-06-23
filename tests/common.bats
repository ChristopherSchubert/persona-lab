setup() { source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"; }

@test "pl_repo_root returns the git toplevel" {
  run pl_repo_root
  [ "$status" -eq 0 ]
  [ -d "$output" ]
}

@test "pl_manifest_get: reads a top-level scalar via yq or fallback" {
  local mf; mf="$(pl_config_dir)/manifest.yml"
  mkdir -p "$(dirname "$mf")"; printf 'grain: single\n' > "$mf"
  run pl_manifest_get grain
  [ "$status" -eq 0 ]; [ "$output" = "single" ]
  rm -f "$mf"
}

@test "pl_manifest_get: nested key without yq fails closed (no silent default)" {
  # only meaningful when yq is absent; if yq is present this asserts the yq path returns the value
  local mf; mf="$(pl_config_dir)/manifest.yml"
  mkdir -p "$(dirname "$mf")"; printf 'engagement:\n  developer:\n    capacity: writes\n' > "$mf"
  run pl_manifest_get engagement.developer.capacity
  if command -v yq >/dev/null 2>&1; then [ "$status" -eq 0 ] && [ "$output" = "writes" ]; else [ "$status" -ne 0 ]; fi
  rm -f "$mf"
}
