setup() {
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in "issue create") echo "https://github.com/o/r/issues/42";; esac
SH
  chmod +x "$PL_TEST_BIN/gh"; export PL_GH_LOG="$(mktemp)"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG"; }

@test "queue file: creates an issue and embeds the W1 envelope + record type" {
  run scripts/queue.sh file --persona "Ben" --tier "finances Team · Developer" \
      --type FINDING --title "clock skew 401" --body "details"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'issues/42'
  grep -q "issue create" "$PL_GH_LOG"
  grep -q -- "--body" "$PL_GH_LOG" && grep -q "FINDING" "$PL_GH_LOG"
  grep -q 'align="left"' "$PL_GH_LOG"   # W1 float header
  grep -q "shields.io/badge" "$PL_GH_LOG"  # record type as a badge
  if grep -q "br clear" "$PL_GH_LOG"; then false; fi  # no <br clear> — that caused the 2-row offset
  grep -q "Developer" "$PL_GH_LOG"         # role shown (tier chip dropped per spec)
  if grep -q "🤖" "$PL_GH_LOG"; then false; fi  # no robot emoji
}

@test "queue file: envelope embeds the persona avatar img" {
  run scripts/queue.sh file --persona "Ben" --tier "finances Team · Developer" --type FINDING --title t --body b
  [ "$status" -eq 0 ]
  grep -q "avatars/ben/ben-64.png" "$PL_GH_LOG"
}

@test "queue comment: appends an enveloped comment to an issue" {
  run scripts/queue.sh comment 42 --persona Ben --tier "finances Team · Developer" --type PROOF --body "fixed"
  [ "$status" -eq 0 ]; grep -q "issue comment 42" "$PL_GH_LOG"
  grep -q "PROOF" "$PL_GH_LOG"
}

@test "queue label: adds a label" {
  run scripts/queue.sh label 42 --add needs-human:decision
  [ "$status" -eq 0 ]; grep -q "issue edit 42 --add-label needs-human:decision" "$PL_GH_LOG"
}

@test "queue close: closes with a state-reason" {
  run scripts/queue.sh close 42 --reason completed
  [ "$status" -eq 0 ]; grep -q "issue close 42" "$PL_GH_LOG"
  grep -q -- "--reason completed" "$PL_GH_LOG"
}

@test "queue query: passes a search and requests json" {
  run scripts/queue.sh query --label needs-human:decision
  [ "$status" -eq 0 ]; grep -q "issue list" "$PL_GH_LOG"
  grep -q -- "--json number,title,labels,state" "$PL_GH_LOG"
}

@test "queue file --repo: targets the named repo" {
  run scripts/queue.sh file --repo o/r --persona Ben --tier "t · Developer" --type FINDING --title x --body y
  [ "$status" -eq 0 ]; grep -q -- "--repo o/r" "$PL_GH_LOG"
}

@test "queue query --repo: targets the named repo" {
  run scripts/queue.sh query --repo o/r --label needs-human:decision
  [ "$status" -eq 0 ]; grep -q -- "--repo o/r" "$PL_GH_LOG"
}

@test "queue file without --repo: no stray --repo flag" {
  run scripts/queue.sh file --persona Ben --tier "t · Developer" --type FINDING --title x --body y
  [ "$status" -eq 0 ]
  if grep -q -- "--repo" "$PL_GH_LOG"; then false; fi
}

@test "queue query without --repo: no stray --repo flag" {
  run scripts/queue.sh query --label needs-human:decision
  [ "$status" -eq 0 ]
  if grep -q -- "--repo" "$PL_GH_LOG"; then false; fi
}

@test "queue label --repo (any order) targets the repo" {
  run scripts/queue.sh label 7 --repo o/r --add needs-human:decision
  [ "$status" -eq 0 ]; grep -q -- "--repo o/r" "$PL_GH_LOG"; grep -q -- "--add-label needs-human:decision" "$PL_GH_LOG"
}
