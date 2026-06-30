# cycle.bats — the conductor: one full SDLC pass chaining the reactors in order
# (triage-reviews → dispatch → integrate → accept). Each stage is overridable via PL_*_SH so the
# test can stub them and assert order/passthrough without running the real reactors.
setup() {
  export PL_TEST_BIN="$(mktemp -d)"
  export PL_ORDER_LOG="$(mktemp)"
  export PL_BOT_ENV="$PL_TEST_BIN/no-bot.env"  # default: no bot identity in tests
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

@test "cycle: --repo exports PL_REPO so every stage sees it" {
  cat > "$PL_DISPATCH_SH" <<'SH'
#!/usr/bin/env bash
echo "dispatch PL_REPO=$PL_REPO" >> "$PL_ORDER_LOG"
SH
  chmod +x "$PL_DISPATCH_SH"
  run scripts/cycle.sh --repo acme/test-repo
  [ "$status" -eq 0 ]
  grep -qF "PL_REPO=acme/test-repo" "$PL_ORDER_LOG"
}

# ── Optional bot identity (#218 — always optional, never enforced) ────────────────────────

@test "cycle: with no bot.env, runs as your own identity (no error, normal pass)" {
  # PL_BOT_ENV (set in setup) points at a nonexistent file → the absent path.
  run scripts/cycle.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE "no bot.env|your own"
  # all stages still ran
  [ "$(awk '{print $1}' "$PL_ORDER_LOG" | tr '\n' ' ')" = "triage dispatch integrate accept " ]
}

@test "cycle: sources PL_BOT_ENV when present (opt-in bot identity)" {
  local be="$PL_TEST_BIN/bot.env"
  printf 'export PL_BOT_MARK=loaded\n' > "$be"
  export PL_BOT_ENV="$be"
  # a stub stage echoes the sourced marker so we can prove it was loaded into the env
  cat > "$PL_DISPATCH_SH" <<'SH'
#!/usr/bin/env bash
echo "dispatch PL_BOT_MARK=$PL_BOT_MARK" >> "$PL_ORDER_LOG"
SH
  chmod +x "$PL_DISPATCH_SH"
  run scripts/cycle.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiF "bot identity loaded"
  grep -qF "PL_BOT_MARK=loaded" "$PL_ORDER_LOG"
}
