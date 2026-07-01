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
  [ "$(grep -c '^triage'    "$PL_ORDER_LOG")" -eq 3 ]
  [ "$(grep -c '^dispatch'  "$PL_ORDER_LOG")" -eq 3 ]
  [ "$(grep -c '^integrate' "$PL_ORDER_LOG")" -eq 3 ]
  [ "$(grep -c '^accept'    "$PL_ORDER_LOG")" -eq 3 ]
  # MUTATION PROOF: change --rounds 3 to --rounds 1 → grep -c returns 1, this fails.
}

@test "cycle: --drain loops until no state:ready issues remain" {
  # Use a file counter — env vars don't survive across gh subprocess calls.
  # _ready_count is called twice per pass: pre-pass count (pre_count) + post-pass remaining check.
  # 2 passes × 2 calls/pass = 4 calls. Return 2 for calls 1-3, 0 for call 4 so pass 2 drains.
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
  # ran exactly 2 passes (stub is deterministic: 4 calls → 2 passes)
  [ "$(grep -c '^dispatch' "$PL_ORDER_LOG")" -eq 2 ]
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

@test "cycle: --drain --dry-run exits non-zero (mutually incompatible)" {
  run scripts/cycle.sh --drain --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "drain|dry.run|incompatible"
  # MUTATION PROOF: remove the guard → --drain runs indefinitely (never reaches 0 in dry-run).
}

@test "cycle: --drain and --rounds are mutually exclusive" {
  run scripts/cycle.sh --drain --rounds 3
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "mutually exclusive|drain|rounds"
}

@test "cycle: --drain --rounds 1 is also rejected (explicit --rounds always conflicts with --drain)" {
  run scripts/cycle.sh --drain --rounds 1
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "mutually exclusive|drain|rounds"
  # MUTATION PROOF: guard using [ rounds -ne 1 ] → passes silently for --rounds 1, this fails.
}

@test "cycle: --rounds with no value exits non-zero with clear message" {
  run scripts/cycle.sh --rounds
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "requires a value|positive integer|rounds"
}

@test "cycle: --rounds N --dry-run forwards --dry-run to all stages in every pass" {
  run scripts/cycle.sh --rounds 3 --dry-run
  [ "$status" -eq 0 ]
  # 4 stages × 3 passes = 12 --dry-run occurrences in the order log
  [ "$(grep -c -- '--dry-run' "$PL_ORDER_LOG")" -eq 12 ]
  # MUTATION PROOF: --rounds 1 → only 4 occurrences, this fails.
}

@test "cycle: --rounds 0 is rejected (requires positive integer)" {
  run scripts/cycle.sh --rounds 0
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "positive integer|rounds"
}

@test "cycle: --rounds banana is rejected (non-integer)" {
  run scripts/cycle.sh --rounds banana
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "positive integer|rounds"
}

@test "cycle: --drain aborts (non-zero) if gh fails in _ready_count (no false-complete)" {
  # A failing gh must NOT produce a silent "drain complete" — it must abort visibly.
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$PL_TEST_BIN/gh"
  PL_REPO=test/repo PATH="$PL_TEST_BIN:$PATH" run scripts/cycle.sh --drain
  [ "$status" -ne 0 ]
  echo "$output" | grep -qiE "gh error|false.complete|cannot determine"
  # MUTATION PROOF: restore || echo 0 → exits 0 with "drain complete", this status check fails.
}

@test "cycle: --drain safety cap (PL_DRAIN_MAX_PASSES) fires after N passes" {
  # gh always returns work remaining → drain would loop forever without the cap.
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
printf '5\n'
SH
  chmod +x "$PL_TEST_BIN/gh"
  PL_REPO=test/repo PL_DRAIN_MAX_PASSES=2 PATH="$PL_TEST_BIN:$PATH" run scripts/cycle.sh --drain
  [ "$status" -ne 0 ]
  [ "$(grep -c '^dispatch' "$PL_ORDER_LOG")" -eq 2 ]
  echo "$output" | grep -qiE "cap|max.passes|safety"
  # MUTATION PROOF: remove the cap check → loop runs forever, test times out.
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
