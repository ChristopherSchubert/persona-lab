# cycle.bats — the conductor: one full SDLC pass chaining the reactors in order
# (triage-reviews → dispatch → integrate → accept). Each stage is overridable via PL_*_SH so the
# test can stub them and assert order/passthrough without running the real reactors.
setup() {
  export PL_TEST_BIN="$(mktemp -d)"
  export PL_ORDER_LOG="$(mktemp)"
  for s in triage dispatch integrate accept; do
    cat > "$PL_TEST_BIN/$s" <<SH
#!/usr/bin/env bash
echo "$s \$*" >> "$PL_ORDER_LOG"
SH
    chmod +x "$PL_TEST_BIN/$s"
  done
  export PL_TRIAGE_SH="$PL_TEST_BIN/triage"
  export PL_DISPATCH_SH="$PL_TEST_BIN/dispatch"
  export PL_INTEGRATE_SH="$PL_TEST_BIN/integrate"
  export PL_ACCEPT_SH="$PL_TEST_BIN/accept"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_ORDER_LOG"; }

@test "cycle: runs triage-reviews → dispatch → integrate → accept, in that order" {
  run scripts/cycle.sh
  [ "$status" -eq 0 ]
  # exact order
  [ "$(awk '{print $1}' "$PL_ORDER_LOG" | tr '\n' ' ')" = "triage dispatch integrate accept " ]
}

@test "cycle: --dry-run passes --dry-run to every stage" {
  run scripts/cycle.sh --dry-run
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--dry-run' "$PL_ORDER_LOG")" -eq 4 ]
}

@test "cycle: a failing stage does not abort the remaining stages (best-effort pass)" {
  cat > "$PL_DISPATCH_SH" <<'SH'
#!/usr/bin/env bash
echo "dispatch $*" >> "$PL_ORDER_LOG"
exit 1
SH
  chmod +x "$PL_DISPATCH_SH"
  run scripts/cycle.sh
  [ "$status" -eq 0 ]
  # integrate and accept still ran after dispatch failed
  grep -q '^integrate' "$PL_ORDER_LOG"
  grep -q '^accept' "$PL_ORDER_LOG"
}

@test "cycle: --drain is refused until worktree isolation (#109) lands" {
  run scripts/cycle.sh --drain
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "drain|#109|isolation"
}
