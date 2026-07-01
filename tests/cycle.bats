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

@test "cycle: --rounds N runs exactly N passes" {
  run scripts/cycle.sh --rounds 3
  [ "$status" -eq 0 ]
  # each stage appears exactly 3 times
  [ "$(grep -c '^dispatch' "$PL_ORDER_LOG")" -eq 3 ]
  [ "$(grep -c '^integrate' "$PL_ORDER_LOG")" -eq 3 ]
  # MUTATION PROOF: change --rounds 3 to --rounds 1 → grep -c returns 1, this fails.
}

@test "cycle: --drain loops until no state:ready issues remain" {
  # Use a file counter — env vars don't survive across gh subprocess calls.
  # _ready_count calls gh twice per pass (header + tail check); need 2 passes → 4 calls.
  # Return 2 for calls 1-3, 0 for call 4 so pass 2 ends and drains.
  local ctr="$PL_TEST_BIN/.gh_calls"
  echo 0 > "$ctr"
  cat > "$PL_TEST_BIN/gh" <<SH
#!/usr/bin/env bash
n=\$(cat "$ctr"); n=\$((n+1)); echo \$n > "$ctr"
if [ "\$n" -le 3 ]; then printf '2\n'; else printf '0\n'; fi
SH
  chmod +x "$PL_TEST_BIN/gh"
  PL_REPO=test/repo PATH="$PL_TEST_BIN:$PATH" run scripts/cycle.sh --drain
  [ "$status" -eq 0 ]
  # ran at least 2 passes (once with remaining work, once to drain)
  [ "$(grep -c '^dispatch' "$PL_ORDER_LOG")" -ge 2 ]
  echo "$output" | grep -q "drain complete"
  # MUTATION PROOF: remove _ready_count loop → only 1 dispatch, count assertion fails.
}

@test "cycle: --drain with zero ready issues runs exactly one pass then stops" {
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
printf '0\n'
SH
  chmod +x "$PL_TEST_BIN/gh"
  PL_REPO=test/repo PATH="$PL_TEST_BIN:$PATH" run scripts/cycle.sh --drain
  [ "$status" -eq 0 ]
  [ "$(grep -c '^dispatch' "$PL_ORDER_LOG")" -eq 1 ]
  echo "$output" | grep -q "drain complete"
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
