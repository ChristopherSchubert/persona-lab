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

# ── pl_envelope structural render guard (#33) ─────────────────────────────────────────
# The greps in queue.bats assert on the `gh` SHELL ARGS — that some substring reached the
# command — not that the envelope RENDERS correctly. They cannot catch the 2-row-offset
# regression: a newline splitting the avatar from the name leaves every old substring
# (`align="left"`, `shields.io/badge`, the avatar path, no `br clear`) intact while breaking
# the float into two rows on GitHub. These guards assert on the actual structured pl_envelope
# output LINE BY LINE, so the single-row float invariant is what's under test.

@test "pl_envelope: header is ONE line — avatar, bold name, and badge all on line 1 (no 2-row offset)" {
  run pl_envelope "Ben" "finances Team · Developer" ASSESSMENT "details"
  [ "$status" -eq 0 ]
  local header; header="$(sed -n '1p' <<<"$output")"
  # All three float elements must share line 1; a 2-row-offset regression moves one to line 2.
  grep -qF 'avatars/ben/ben-64.png' <<<"$header"
  grep -qF 'width="44" align="left">' <<<"$header"   # avatar float
  grep -qF '**Ben**' <<<"$header"                    # bold name, same line
  grep -qF 'img.shields.io/badge/ASSESSMENT-' <<<"$header"
  grep -qF 'height="16" align="texttop">' <<<"$header"  # badge alignment, same line
}

@test "pl_envelope: line 2 is the AI · role flag with the role only (tier prefix dropped)" {
  run pl_envelope "Ben" "finances Team · Developer" ASSESSMENT "details"
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' <<<"$output")" = '`AI` · Developer' ]
}

@test "pl_envelope: body follows a blank separator line, not glued to the header" {
  run pl_envelope "Ben" "finances Team · Developer" ASSESSMENT "the body"
  [ "$status" -eq 0 ]
  [ -z "$(sed -n '3p' <<<"$output")" ]              # blank separator
  [ "$(sed -n '4p' <<<"$output")" = "the body" ]
}

@test "pl_envelope: no <br clear> and no robot emoji anywhere (both reintroduce the offset/legacy chrome)" {
  run pl_envelope "Ben" "finances Team · Developer" ASSESSMENT "details"
  [ "$status" -eq 0 ]
  if grep -qF 'br clear' <<<"$output"; then false; fi
  if grep -qF '🤖' <<<"$output"; then false; fi
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

# ── pl_extract_json (#153) ────────────────────────────────────────────────────────────
# Strengthened parser: prefer the FINAL ```-fenced block; degraded scan returns the LAST
# top-level value — so a JSON *example* that precedes the real record can never win.
# (common.sh is already sourced by setup(), so pl_extract_json is callable directly; we
#  feed input via a here-string so each case is self-contained and cwd-independent.)

@test "pl_extract_json: clean JSON object passes through" {
  run pl_extract_json <<<'{"record_type":"DELIVERED","body":"x"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r .record_type <<<"$output")" = "DELIVERED" ]
}

@test "pl_extract_json: clean JSON array passes through" {
  run pl_extract_json <<<'[{"title":"a"}]'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "a" ]
}

@test "pl_extract_json: live #8 — object as final fenced block after bracketed prose" {
  # The dropped DELIVERED: prose carried '[--grace-min N]' before the fenced JSON object.
  local in
  in='I added the `[--grace-min N]` flag and closed #8.

```json
{"record_type":"DELIVERED","body":"PR #148, 17/17 tests"}
```'
  run pl_extract_json <<<"$in"
  [ "$status" -eq 0 ]
  [ "$(jq -r .record_type <<<"$output")" = "DELIVERED" ]
  [ "$(jq -r .body <<<"$output")" = "PR #148, 17/17 tests" ]
}

@test "pl_extract_json: live design-analyst — array as final fenced block after **[roster]** prose" {
  local in
  in='The zero-state **[roster]** copy is inert.

```json
[{"title":"Zero-state microcopy drift","priority":"p2"}]
```'
  run pl_extract_json <<<"$in"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "Zero-state microcopy drift" ]
}

@test "pl_extract_json: Greg's-review case — JSON example in an EARLIER fence, record in the LAST fence" {
  # A review *of a parser* is saturated with JSON examples. The real record is the FINAL fence;
  # an earlier fenced example must NOT be returned.
  local in
  in='Reviewing the parser. The old greedy match grabbed:

```json
{"example":"not the record","record_type":"BOGUS"}
```

That is wrong. Here is my actual review:

```json
{"record_type":"REVIEW","body":"request changes: fenced-only"}
```'
  run pl_extract_json <<<"$in"
  [ "$status" -eq 0 ]
  [ "$(jq -r .record_type <<<"$output")" = "REVIEW" ]
  [ "$(jq -r .body <<<"$output")" = "request changes: fenced-only" ]
}

@test "pl_extract_json: unfenced — JSON example BEFORE the real record returns the LAST value" {
  local in
  in='For example a finding looks like {"title":"sample","priority":"p3"} but my real record is:
{"record_type":"ASSESSMENT","body":"the real one"}'
  run pl_extract_json <<<"$in"
  [ "$status" -eq 0 ]
  [ "$(jq -r .record_type <<<"$output")" = "ASSESSMENT" ]
  [ "$(jq -r .body <<<"$output")" = "the real one" ]
}

@test "pl_extract_json: unfenced prose-wrapped single object still works (regression guard)" {
  run pl_extract_json <<<'Here is my record: {"record_type":"REPLY","body":"hi"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r .record_type <<<"$output")" = "REPLY" ]
}

@test "pl_extract_json: unparseable prose returns non-zero" {
  run pl_extract_json <<<'no json here, just prose with a stray [bracket] and {brace'
  [ "$status" -ne 0 ]
}
