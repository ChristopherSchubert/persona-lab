# triage-reviews.bats — the PM review-triage pass (#149/#196): the produce→review trigger. The PM
# (Sarah) is dispatched with the open PRs awaiting review and returns each routed to its gate owner(s)
# per the RACI; the harness files the review tasks routed (persona:<slug> + state:ready) so the normal
# dispatch cycle picks them up. gh + claude are stubbed; NO real model call or issue is created.
setup() {
  export PL_RUNS_DIR="$(mktemp -d)/runs"
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_GH_LOG="$(mktemp)"
  export PL_FAKE_PRS="$(mktemp)"
  export PL_FAKE_ISSUES="$(mktemp)"; printf '[]' > "$PL_FAKE_ISSUES"

  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
case "$1 $2" in
  "pr list")    jq '[.[] | {number, title, labels, files}]' "$PL_FAKE_PRS" ;;
  "issue list") cat "$PL_FAKE_ISSUES" ;;
  "issue create") echo "https://github.com/acme/persona-lab/issues/777" ;;
  "repo view")  echo "acme/persona-lab" ;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
  export PL_REPO="persona-lab"

  # claude stub returns whatever PL_FAKE_TRIAGE holds as the model "result".
  export PL_FAKE_TRIAGE="$(mktemp)"
  cat > "$PL_TEST_BIN/fake-claude" <<'SH'
#!/usr/bin/env bash
echo "CLAUDE $*" >> "$PL_GH_LOG"
printf '{"result":%s}' "$(jq -Rs . < "$PL_FAKE_TRIAGE")"
SH
  chmod +x "$PL_TEST_BIN/fake-claude"
  export PL_CLAUDE="$PL_TEST_BIN/fake-claude"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG" "$PL_FAKE_PRS" "$PL_FAKE_ISSUES" "$PL_FAKE_TRIAGE" "$(dirname "$PL_RUNS_DIR")"; }

fake_prs()    { printf '%s' "$1" > "$PL_FAKE_PRS"; }
fake_triage() { printf '%s' "$1" > "$PL_FAKE_TRIAGE"; }   # the JSON array Sarah "returns"

@test "triage-reviews: files an eng review task routed persona:lead-engineer + state:ready" {
  fake_prs '[{"number":190,"title":"isolation","labels":[],"files":[{"path":"scripts/dispatch.sh"}]}]'
  fake_triage '```json
[{"pr":190,"reviewer":"lead-engineer","priority":"p1","title":"Review PR #190 — Lead Engineer","body":"Review the worktree isolation change."}]
```'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  grep -qE "issue create" "$PL_GH_LOG"
  grep -qE "(add-label|--label).*persona:lead-engineer" "$PL_GH_LOG"
  grep -qE "(add-label|--label).*state:ready" "$PL_GH_LOG"
}

@test "triage-reviews: files a QA review task when Sarah routes head-of-qa" {
  fake_prs '[{"number":190,"title":"isolation","labels":[],"files":[{"path":"scripts/dispatch.sh"}]}]'
  fake_triage '```json
[{"pr":190,"reviewer":"head-of-qa","priority":"p1","title":"Review PR #190 — Head of QA","body":"QA the scripts change."}]
```'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  grep -qE "(add-label|--label).*persona:head-of-qa" "$PL_GH_LOG"
}

@test "triage-reviews: does NOT offer PRs already gate:eng-approved or merged to the PM" {
  # Both PRs are already past review; the PM should be given an empty pending set → no claude call.
  fake_prs '[
    {"number":1,"title":"done","labels":[{"name":"gate:eng-approved"}],"files":[{"path":"a.md"}]},
    {"number":2,"title":"merged","labels":[{"name":"state:merged"}],"files":[{"path":"b.md"}]},
    {"number":3,"title":"accepted","labels":[{"name":"state:accepted"}],"files":[{"path":"c.md"}]}
  ]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "^CLAUDE|issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: routes a visual PR to head-of-design when the PM says so" {
  fake_prs '[{"number":210,"title":"new banner","labels":[],"files":[{"path":"assets/banner.svg"}]}]'
  fake_triage '```json
[{"pr":210,"reviewer":"head-of-design","priority":"p2","title":"Review PR #210 — Head of Design","body":"Design sign-off on the banner."}]
```'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  grep -qE "(add-label|--label).*persona:head-of-design" "$PL_GH_LOG"
}

@test "triage-reviews: a junk PM response files nothing and exits 0 (fail-safe)" {
  fake_prs '[{"number":190,"title":"isolation","labels":[],"files":[{"path":"scripts/x.sh"}]}]'
  fake_triage 'I cannot help with that.'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: dedup — an already-open review task for the PR is not re-filed" {
  fake_prs '[{"number":190,"title":"isolation","labels":[],"files":[{"path":"scripts/x.sh"}]}]'
  printf '%s' '[{"title":"Review PR #190 — Lead Engineer"}]' > "$PL_FAKE_ISSUES"
  fake_triage '```json
[{"pr":190,"reviewer":"lead-engineer","priority":"p1","title":"Review PR #190 — Lead Engineer","body":"dup"}]
```'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: an unknown reviewer slug is rejected (not a gate owner)" {
  fake_prs '[{"number":190,"title":"isolation","labels":[],"files":[{"path":"a.md"}]}]'
  fake_triage '```json
[{"pr":190,"reviewer":"intern","priority":"p1","title":"Review PR #190 — Intern","body":"nope"}]
```'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: --dry-run files nothing" {
  fake_prs '[{"number":190,"title":"isolation","labels":[],"files":[{"path":"scripts/x.sh"}]}]'
  fake_triage '```json
[{"pr":190,"reviewer":"lead-engineer","priority":"p1","title":"Review PR #190 — Lead Engineer","body":"x"}]
```'
  run scripts/triage-reviews.sh --dry-run
  [ "$status" -eq 0 ]
  if grep -qE "issue create" "$PL_GH_LOG"; then false; fi
}

@test "triage-reviews: no PRs awaiting review exits 0 without dispatching the PM" {
  fake_prs '[]'
  run scripts/triage-reviews.sh
  [ "$status" -eq 0 ]
  if grep -qE "^CLAUDE|issue create" "$PL_GH_LOG"; then false; fi
}
