# setup-labels.bats — the canonical label set is provisioned reproducibly (gh stubbed; no network).
setup() {
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
exit 0
SH
  chmod +x "$PL_TEST_BIN/gh"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG"; }

@test "setup-labels: provisions the state:proposed triage inbox label (#93/#129)" {
  run scripts/setup-labels.sh
  [ "$status" -eq 0 ]
  grep -qF "label create state:proposed" "$PL_GH_LOG"
  # MUTATION PROOF: delete the state:proposed mk line in setup-labels.sh → this grep fails.
}

@test "setup-labels: still provisions state:ready (no regression)" {
  run scripts/setup-labels.sh
  [ "$status" -eq 0 ]
  grep -qF "label create state:ready" "$PL_GH_LOG"
}
