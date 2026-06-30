#!/usr/bin/env bats
# P4B tests for scripts/watchdog.sh

setup() { export PL_RUNS="$(mktemp -d)"; }
teardown() { rm -rf "$PL_RUNS"; }

@test "watchdog: flags a stale pending wake" {
  old="$(date -u -v-90M +%FT%TZ 2>/dev/null || date -u -d '90 minutes ago' +%FT%TZ)"
  printf '{"ts":"%s","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"pending","cost_tokens":0}\n' "$old" > "$PL_RUNS/x.ndjson"
  run scripts/watchdog.sh scan --grace-min 30
  [ "$status" -eq 0 ]; echo "$output" | grep -qi "Sam"
}

@test "watchdog: a recent pending is NOT flagged" {
  now="$(date -u +%FT%TZ)"
  printf '{"ts":"%s","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"pending","cost_tokens":0}\n' "$now" > "$PL_RUNS/x.ndjson"
  run scripts/watchdog.sh scan --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -qi "Sam"; then false; fi
}

@test "watchdog: a terminal (acted) record is never flagged" {
  old="$(date -u -v-90M +%FT%TZ 2>/dev/null || date -u -d '90 minutes ago' +%FT%TZ)"
  printf '{"ts":"%s","persona":"Sam","repo":"r","trigger":"on-demand","outcome":"acted","cost_tokens":10}\n' "$old" > "$PL_RUNS/x.ndjson"
  run scripts/watchdog.sh scan --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -qi "Sam"; then false; fi
}

# ── stale-lock recovery (issue #8) ────────────────────────────────────────────
# Interrupted-dispatch simulation: a writer lock minted in the past with no live
# run, left orphaned because the EXIT trap never fired (hard kill).

setup_locks() {
  export PL_GH_STATE="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
}

@test "reclaim-locks: detects a stale lock, files an issue, leaves writes unblocked" {
  setup_locks
  # mint a lock dated 90 minutes ago (interrupted dispatch left it behind)
  PL_GH_FAKE_DATE="$(date -u -v-90M +%FT%TZ 2>/dev/null || date -u -d '90 minutes ago' +%FT%TZ)" \
    scripts/lock.sh claim --repo finances --holder Doug >/dev/null
  run scripts/watchdog.sh reclaim-locks --grace-min 30
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "RECLAIMED"
  echo "$output" | grep -q "finances"
  echo "$output" | grep -qi "issues/"          # an incident issue was filed
  # an archive of the orphaned lock was preserved
  echo "$output" | grep -q "persona-lock-archive/finances/"
  # end state: the lock is FREE — every further write is unblocked
  [ "$(scripts/lock.sh status --repo finances)" = "free" ]
}

@test "reclaim-locks: a fresh (active) lock is NOT reclaimed" {
  setup_locks
  scripts/lock.sh claim --repo finances --holder Doug >/dev/null   # dated now
  run scripts/watchdog.sh reclaim-locks --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "RECLAIMED"; then false; fi
  [ "$(scripts/lock.sh status --repo finances)" = "held" ]
}

@test "reclaim-locks: no locks present is a clean no-op" {
  setup_locks
  run scripts/watchdog.sh reclaim-locks --grace-min 30
  [ "$status" -eq 0 ]
  if echo "$output" | grep -q "RECLAIMED"; then false; fi
}

# Race: a live writer re-claims the lock in the window between the watchdog
# assessing it stale and the guarded delete. The fence guard must skip the delete
# (never nuke a live writer's lock) and surface it — no recreate, no blind release.
@test "reclaim-locks: a live re-claim mid-recovery is skipped, live lock left intact" {
  setup_locks
  # mint a STALE orphan (interrupted dispatch left it 90 min ago)
  PL_GH_FAKE_DATE="$(date -u -v-90M +%FT%TZ 2>/dev/null || date -u -d '90 minutes ago' +%FT%TZ)" \
    scripts/lock.sh claim --repo finances --holder Doug >/dev/null
  # the instant the watchdog reads the ref (its inspect), a live writer re-claims it:
  # the stub swaps the ref to a fresh fence on that first single-ref GET.
  export PL_GH_SWAP_REF="refs/heads/persona-lock/finances"
  export PL_GH_SWAP_SHA="ffffffffffffffffffffffffffffffffffffffff"
  run scripts/watchdog.sh reclaim-locks --grace-min 30
  unset PL_GH_SWAP_REF PL_GH_SWAP_SHA
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SKIPPED"
  # the fence guard prevented the delete — the live writer's lock is intact (mutation-proof)
  [ "$(scripts/lock.sh status --repo finances)" = "held" ]
  # a benign live re-claim is not an incident: nothing was reclaimed
  if echo "$output" | grep -q "RECLAIMED"; then false; fi
}
# `watchdog.sh prune-worktrees` sweeps the worktree root and removes any dir older than the
# grace window — mirroring the reclaim-locks pattern. `git` is stubbed so the sweep is
# observable without a real checkout; the stub rm's the dir on `worktree remove`.
_stub_git_wt() {
  export PL_GIT_LOG="$(mktemp)"; export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  cat > "$PL_TEST_BIN/git" <<'SH'
#!/usr/bin/env bash
echo "GIT $*" >> "$PL_GIT_LOG"
if [ "$1" = "worktree" ] && [ "$2" = "remove" ]; then rm -rf "$4"; fi
exit 0
SH
  chmod +x "$PL_TEST_BIN/git"
}

@test "watchdog: prune-worktrees removes a leaked worktree older than the grace window" {
  _stub_git_wt
  wt_root="$(mktemp -d)/wt"; mkdir -p "$wt_root/developer-11"
  touch -t 200001010000 "$wt_root/developer-11" 2>/dev/null \
    || touch -d '2000-01-01' "$wt_root/developer-11"
  PL_WT_ROOT="$wt_root" run scripts/watchdog.sh prune-worktrees --grace-min 30
  [ "$status" -eq 0 ]
  grep -qF "worktree remove" "$PL_GIT_LOG"
  echo "$output" | grep -qiF "pruned"
  [ ! -d "$wt_root/developer-11" ]
  rm -rf "${wt_root%/wt}"
  # MUTATION PROOF: skip the prune-worktrees subcommand → no "worktree remove", this fails.
}

@test "watchdog: prune-worktrees leaves a FRESH worktree alone (within grace)" {
  _stub_git_wt
  wt_root="$(mktemp -d)/wt"; mkdir -p "$wt_root/developer-12"   # just created → fresh
  PL_WT_ROOT="$wt_root" run scripts/watchdog.sh prune-worktrees --grace-min 30
  [ "$status" -eq 0 ]
  [ -d "$wt_root/developer-12" ]                                 # not pruned — still in use
  if grep -qF "worktree remove" "$PL_GIT_LOG"; then false; fi
  rm -rf "${wt_root%/wt}"
  # MUTATION PROOF: drop the mtime/grace filter → the fresh worktree is removed, this fails.
}
