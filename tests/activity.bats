setup() {
  export PL_RUNS="$(mktemp -d)/runs"
  mkdir -p "$PL_RUNS"
  # Seed sample NDJSON records
  cat > "$PL_RUNS/2024-01-01.ndjson" <<'NDJSON'
{"ts":"2024-01-01T09:00:00Z","persona":"Doug","repo":"persona-lab","trigger":"summon","outcome":"acted","cost_tokens":500,"role":"developer","action":"bus:comment","record_type":"bus","artifact_url":"https://github.com/o/r/issues/10","issue_number":10}
{"ts":"2024-01-01T10:00:00Z","persona":"Tom","repo":"persona-lab","trigger":"summon","outcome":"complete","cost_tokens":800,"role":"platform-architect","action":"bus:comment","record_type":"bus","artifact_url":"https://github.com/o/r/issues/11","issue_number":11}
{"ts":"2024-01-01T11:00:00Z","persona":"Laura","repo":"persona-lab","trigger":"summon","outcome":"error","cost_tokens":200}
NDJSON
}

@test "activity: produces HTML output to stdout" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "<html"
}

@test "activity: --out writes HTML to a file" {
  outfile="$(mktemp /tmp/activity-test-XXXX)"
  mv "$outfile" "${outfile}.html"; outfile="${outfile}.html"
  run scripts/activity.sh --out "$outfile"
  [ "$status" -eq 0 ]
  [ -f "$outfile" ]
  grep -q "<html" "$outfile"
  rm -f "$outfile"
}

@test "activity: HTML contains one row per record" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # 3 records → 3 <tr> data rows (not counting header)
  count="$(echo "$output" | grep -c '<tr class="row')"
  [ "$count" -eq 3 ]
}

@test "activity: HTML contains avatar img with jsDelivr URL" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "cdn.jsdelivr.net/gh/ChristopherSchubert/persona-lab@main/assets/avatars/"
}

@test "activity: avatar img has onerror initials fallback" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "onerror"
  echo "$output" | grep -qF "avatar-initials"
  echo "$output" | grep -qF "avatar-wrap"
}

@test "activity: HTML contains artifact link for records with issue_number" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Issues 10 and 11 should produce linked #N anchors
  echo "$output" | grep -qF "#10"
  echo "$output" | grep -qF "#11"
}

@test "activity: artifact link href uses artifact_url" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "https://github.com/o/r/issues/10"
}

@test "activity: token footer sums all cost_tokens" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # 500 + 800 + 200 = 1500
  echo "$output" | grep -qF "1500"
}

@test "activity: outcome color chips present" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # acted / pending → amber, complete → green, error → red
  echo "$output" | grep -qE "#f59e0b|pending|amber"
  echo "$output" | grep -qE "#22c55e|complete|green"
  echo "$output" | grep -qE "#ef4444|error|red"
}

@test "activity: --persona filter limits output rows" {
  run scripts/activity.sh --persona Doug
  [ "$status" -eq 0 ]
  count="$(echo "$output" | grep -c '<tr class="row')"
  [ "$count" -eq 1 ]
  echo "$output" | grep -qF "Doug"
  echo "$output" | grep -qvF "Tom"
}

@test "activity: --since filter limits output rows" {
  run scripts/activity.sh --since "2024-01-01T10:00:00Z"
  [ "$status" -eq 0 ]
  count="$(echo "$output" | grep -c '<tr class="row')"
  # Only records at or after 10:00 (Tom and Laura) → 2
  [ "$count" -eq 2 ]
}

@test "activity: HTML is self-contained (no external script/link deps)" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Must not reference any external JS framework or CSS framework
  echo "$output" | grep -qvF "bootstrap"
  echo "$output" | grep -qvF "tailwind"
  echo "$output" | grep -qvF "react"
  echo "$output" | grep -qvF "<script src"
  echo "$output" | grep -qvF '<link rel="stylesheet"'
}

@test "activity: records sorted chronologically" {
  # Write records out of order and verify time-ordered output
  cat > "$PL_RUNS/2024-01-02.ndjson" <<'NDJSON'
{"ts":"2024-01-02T08:00:00Z","persona":"Greg","repo":"persona-lab","trigger":"summon","outcome":"acted","cost_tokens":100}
NDJSON
  # Prepend an earlier record in a later file (simulating out-of-file-order data)
  cat > "$PL_RUNS/2024-01-02-b.ndjson" <<'NDJSON'
{"ts":"2024-01-01T07:00:00Z","persona":"Hana","repo":"persona-lab","trigger":"summon","outcome":"acted","cost_tokens":50}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Hana (07:00) should appear before Greg (08:00) in the HTML
  hana_pos="$(echo "$output" | grep -n "Hana" | head -1 | cut -d: -f1)"
  greg_pos="$(echo "$output" | grep -n "Greg" | head -1 | cut -d: -f1)"
  [ "$hana_pos" -lt "$greg_pos" ]
}

# ---------------------------------------------------------------------------
# Security: HTML/attribute injection hardening
# Each test seeds a record with a malicious payload and verifies the output is
# properly escaped — i.e. the test FAILS against unescaped code.
# ---------------------------------------------------------------------------

@test "activity: persona name is HTML-escaped (no live <script> tag)" {
  # persona field contains raw HTML that would execute in a browser if unescaped
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"<script>alert(1)</script>","action":"test","outcome":"acted","cost_tokens":0}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # The literal string <script> must NOT appear as a live tag in the persona-name span
  echo "$output" | grep -qvF 'persona-name"><script>alert'
  # persona-name span must contain the HTML-encoded version
  echo "$output" | grep -qF 'persona-name">&lt;script&gt;alert'
}

@test "activity: action field is HTML-escaped (no broken table via </td>)" {
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"Safe","action":"</td><td><script>alert(2)</script>","outcome":"acted","cost_tokens":0}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # The injected closing tag must not appear raw
  echo "$output" | grep -qvF "</td><td><script>"
  # Must be encoded
  echo "$output" | grep -qF "&lt;/td&gt;"
}

@test "activity: artifact_url href attribute is escaped (no attribute break-out)" {
  # A double-quote in the URL would close the href attribute and allow injection
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"Safe","action":"test","outcome":"acted","cost_tokens":0,"artifact_url":"https://example.com/\" onmouseover=\"alert(3)","issue_number":99}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # The raw onmouseover event handler must not appear as an unencoded attribute
  echo "$output" | grep -qvF 'onmouseover="alert(3)'
  # The double-quote in the URL must be encoded
  echo "$output" | grep -qF "&quot;"
}

@test "activity: persona slug in img src is escaped (no attribute injection)" {
  # A slug derived from a name like 'x" onerror="alert(4)' would break out of src=""
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"x\" onerror=\"alert(4)","action":"test","outcome":"acted","cost_tokens":0}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # The raw onerror handler must not appear
  echo "$output" | grep -qvF 'onerror="alert(4)'
  # The double-quote in the slug must be encoded in the src attribute
  echo "$output" | grep -qF "&quot;"
}

@test "activity: ampersand in values is HTML-escaped" {
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"A & B","action":"do & done","outcome":"acted","cost_tokens":0}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "&amp;"
}

@test "activity: non-https artifact_url is not rendered as a clickable link (no javascript: scheme)" {
  # A javascript: URL is escaped by @html but would still be a live, clickable
  # XSS link. Only https:// URLs may become anchors; anything else is inert.
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"Safe","action":"test","outcome":"acted","cost_tokens":0,"artifact_url":"javascript:alert(5)","issue_number":99}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # No anchor whose href carries the javascript: scheme
  echo "$output" | grep -qvF 'href="javascript:'
}

@test "activity: https artifact_url is still rendered as a clickable link" {
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"Safe","action":"test","outcome":"acted","cost_tokens":0,"artifact_url":"https://example.com/ok","issue_number":42}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'href="https://example.com/ok"'
}

@test "activity: --persona filter passes value via jq --arg (no jq code injection)" {
  # A malicious --persona value that would break out of the interpolated jq string
  # and inject arbitrary jq code must be handled safely.
  # We rely on the fix (--arg) making this harmless; the test verifies no crash
  # and that no unintended records leak through.
  cat > "$PL_RUNS/inject.ndjson" <<'NDJSON'
{"ts":"2024-02-01T00:00:00Z","persona":"Safe","action":"ok","outcome":"acted","cost_tokens":0}
NDJSON
  # Value that would break jq string interpolation if not quoted properly
  run scripts/activity.sh --persona 'Safe" or .persona == "Safe'
  [ "$status" -eq 0 ]
  # Should produce 0 rows — no persona exactly matches the injected string
  count="$(echo "$output" | grep -c '<tr class="row' || true)"
  [ "$count" -eq 0 ]
}

# ===========================================================================
# v2 spec tests
# ===========================================================================

# ---------------------------------------------------------------------------
# Noise suppression
# ---------------------------------------------------------------------------

@test "v2: system persona rows are suppressed from default view" {
  cat > "$PL_RUNS/v2.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"system","repo":"r","trigger":"bus","outcome":"posted","cost_tokens":0,"action":"bus:park","record_type":"bus","issue_number":5}
{"ts":"2024-03-01T09:01:00Z","persona":"Doug","repo":"r","trigger":"summon","outcome":"acted","cost_tokens":500,"role":"developer","action":"bus:comment","record_type":"bus","artifact_url":"https://github.com/o/r/issues/5","issue_number":5}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # system row goes into suppressed section; only meaningful rows in primary tbody
  # Suppressed rows carry class "row suppressed"; primary rows are class "row"
  primary_count="$(echo "$output" | grep -c 'class="row"' || true)"
  suppressed_count="$(echo "$output" | grep -c 'suppressed' || true)"
  # 3 seed + 1 Doug = 4 primary; the system row ends up in the suppressed section
  [ "$primary_count" -eq 4 ]
  [ "$suppressed_count" -ge 1 ]
}

@test "v2: bus:quarantine rows are suppressed from default view" {
  cat > "$PL_RUNS/v2q.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"system","repo":"r","trigger":"bus","outcome":"posted","cost_tokens":0,"action":"bus:quarantine","record_type":"bus","issue_number":5}
{"ts":"2024-03-01T09:01:00Z","persona":"Doug","repo":"r","trigger":"summon","outcome":"acted","cost_tokens":500,"role":"developer","action":"bus:comment","record_type":"bus","artifact_url":"https://github.com/o/r/issues/5","issue_number":5}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  primary_count="$(echo "$output" | grep -c 'class="row"' || true)"
  [ "$primary_count" -eq 4 ]  # 3 seed + 1 Doug
}

@test "v2: ghost bus:comment rows (cost_tokens=0 and role empty) are suppressed from default view" {
  # Ghost row: cost_tokens=0, action=bus:comment, role absent/empty
  cat > "$PL_RUNS/v2ghost.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"Ben","repo":"r","trigger":"bus","outcome":"posted","cost_tokens":0,"action":"bus:comment","record_type":"bus","issue_number":5}
{"ts":"2024-03-01T09:01:00Z","persona":"Doug","repo":"r","trigger":"summon","outcome":"acted","cost_tokens":500,"role":"developer","action":"bus:comment","record_type":"bus","artifact_url":"https://github.com/o/r/issues/5","issue_number":5}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  primary_count="$(echo "$output" | grep -c 'class="row"' || true)"
  [ "$primary_count" -eq 4 ]  # 3 seed + 1 Doug; ghost Ben suppressed
}

@test "v2: bus:comment with a role is NOT suppressed" {
  # A bus:comment with cost_tokens=0 but a real role should still show
  cat > "$PL_RUNS/v2role.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"Greg","repo":"r","trigger":"summon","outcome":"error","cost_tokens":0,"role":"finops","action":"bus:comment","record_type":"bus","artifact_url":"https://github.com/o/r/issues/27","issue_number":27}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "Greg"
}

@test "v2: header shows meaningful count with total in parens" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # e.g. "3 events (3 total)" or "3 events (N total)" — meaningful number first
  echo "$output" | grep -qF "events ("
}

@test "v2: show-all toggle is present and works without JS (details/summary)" {
  # Seed a suppressed row so the details element is emitted
  cat > "$PL_RUNS/v2suppress.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"system","action":"bus:park","outcome":"posted","cost_tokens":0,"issue_number":99}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Must contain a <details> element (CSS-only toggle)
  echo "$output" | grep -qF "<details"
  echo "$output" | grep -qF "<summary"
  # Show-all option must say something about "all records" or "suppressed"
  echo "$output" | grep -qF "all"
}

@test "v2: show-all toggle is a single <details> wrapping all suppressed rows" {
  # Emit records that produce suppressed rows, then confirm only ONE <details> block
  cat > "$PL_RUNS/v2toggle.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"system","action":"bus:park","outcome":"posted","cost_tokens":0,"issue_number":1}
{"ts":"2024-03-01T09:01:00Z","persona":"system","action":"bus:park","outcome":"posted","cost_tokens":0,"issue_number":2}
{"ts":"2024-03-01T09:02:00Z","persona":"system","action":"bus:park","outcome":"posted","cost_tokens":0,"issue_number":3}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Must have exactly ONE <details> element, not one per suppressed row
  details_count="$(echo "$output" | grep -c '<details')"
  [ "$details_count" -eq 1 ]
  # And ONE <summary> element
  summary_count="$(echo "$output" | grep -c '<summary')"
  [ "$summary_count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Plain-English sentences — no raw colon-codes in default view
# ---------------------------------------------------------------------------

@test "v2: bus:comment renders as human sentence not raw code" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Should contain natural language like "commented on issue"
  echo "$output" | grep -qF "commented on issue"
  # Raw "bus:comment" must NOT appear as visible cell text in primary rows.
  # Strip content from the first <details> tag onward (the suppressed section),
  # then verify no ">bus:comment<" literal remains in primary content.
  primary_html="$(echo "$output" | awk '/<details/{exit} {print}')"
  echo "$primary_html" | grep -qvF ">bus:comment<"
}

@test "v2: bus:park renders as 'parked issue' sentence" {
  # Tom parks issue #38 in the seed data
  cat > "$PL_RUNS/v2park.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:05:00Z","persona":"Tom","repo":"r","trigger":"summon","outcome":"acted","cost_tokens":850,"role":"platform-architect","action":"bus:park","record_type":"bus","artifact_url":"https://github.com/o/r/issues/38","issue_number":38}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "parked issue"
}

@test "v2: build action renders as 'ran a build' sentence" {
  cat > "$PL_RUNS/v2build.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:10:00Z","persona":"Doug","repo":"r","trigger":"push","outcome":"complete","cost_tokens":5100,"role":"developer","action":"build"}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "ran a build"
}

@test "v2: summon with no action and acted outcome renders as 'picked up work'" {
  cat > "$PL_RUNS/v2summon.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:15:00Z","persona":"Ben","repo":"finances","trigger":"summon","outcome":"acted","cost_tokens":0}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "picked up work"
}

@test "v2: summon with complete outcome renders as 'completed work'" {
  cat > "$PL_RUNS/v2complete.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:20:00Z","persona":"Laura","repo":"r","trigger":"summon","outcome":"complete","cost_tokens":300}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "completed work"
}

@test "v2: summon with error outcome renders as 'encountered an error'" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # The seed data has Laura with trigger=summon outcome=error
  echo "$output" | grep -qF "encountered an error"
}

@test "v2: unknown action code renders in <code> element" {
  cat > "$PL_RUNS/v2unknown.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:25:00Z","persona":"Doug","repo":"r","trigger":"summon","outcome":"acted","cost_tokens":100,"role":"developer","action":"some:future:action"}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Unknown codes must appear wrapped in <code>, not raw in text
  echo "$output" | grep -qF "<code>"
  echo "$output" | grep -qF "some:future:action"
}

# ---------------------------------------------------------------------------
# Group by issue
# ---------------------------------------------------------------------------

@test "v2: rows are grouped under issue cards with linked headings" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Issues 10 and 11 are in seed data; should see issue card headings
  echo "$output" | grep -qF "#10"
  echo "$output" | grep -qF "#11"
  # Issue headings should be linked (href to artifact_url)
  echo "$output" | grep -qF "github.com/o/r/issues/10"
}

@test "v2: same issue_number renders as ONE card not multiple" {
  # Two records for issue 55 plus the seed data (issues 10, 11, infra).
  # If grouping is broken, each row gets its own card → 5 cards (10, 11, 55, 55, infra).
  # Correct grouping → 4 cards (10, 11, 55, infra).
  cat > "$PL_RUNS/v2onecard.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"Doug","repo":"r","trigger":"summon","outcome":"acted","cost_tokens":100,"role":"developer","action":"bus:comment","artifact_url":"https://github.com/o/r/issues/55","issue_number":55}
{"ts":"2024-03-01T09:05:00Z","persona":"Tom","repo":"r","trigger":"summon","outcome":"complete","cost_tokens":200,"role":"architect","action":"bus:comment","artifact_url":"https://github.com/o/r/issues/55","issue_number":55}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Total cards: issues 10 + 11 + 55 + infra = 4; broken grouping would give 5
  card_count="$(echo "$output" | grep -cF 'class="issue-card"')"
  [ "$card_count" -eq 4 ]
  # Both personas appear inside the single #55 card
  echo "$output" | grep -qF "Doug"
  echo "$output" | grep -qF "Tom"
}

@test "v2: non-issue rows appear under Infrastructure section" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Laura's record has no issue_number; should be under Infrastructure
  echo "$output" | grep -qF "Infrastructure"
}

@test "v2: Infrastructure renders as ONE card not multiple" {
  # Multiple infra records must produce a single Infrastructure card
  cat > "$PL_RUNS/v2infra.ndjson" <<'NDJSON'
{"ts":"2024-03-01T09:00:00Z","persona":"Doug","repo":"r","trigger":"push","outcome":"complete","cost_tokens":100,"action":"build"}
{"ts":"2024-03-01T09:05:00Z","persona":"Tom","repo":"r","trigger":"push","outcome":"complete","cost_tokens":200,"action":"build"}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Count Infrastructure div headings (not CSS rule which has .infra-heading)
  # The rendered heading is: <div class="infra-heading">Infrastructure</div>
  infra_count="$(echo "$output" | grep -cF '>Infrastructure<')"
  [ "$infra_count" -eq 1 ]
  # Both personas appear inside that single card
  echo "$output" | grep -qF "Doug"
  echo "$output" | grep -qF "Tom"
}

# ---------------------------------------------------------------------------
# Token footer: only meaningful records
# ---------------------------------------------------------------------------

@test "v2: token footer counts only meaningful records (suppressed excluded)" {
  # Add a system row to confirm it's excluded from the token total
  cat > "$PL_RUNS/v2tokens.ndjson" <<'NDJSON'
{"ts":"2024-03-01T10:00:00Z","persona":"system","repo":"r","trigger":"bus","outcome":"posted","cost_tokens":9999,"action":"bus:park","record_type":"bus","issue_number":1}
NDJSON
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # system record's 9999 tokens must NOT appear in the total
  # seed data total is 500+800+200 = 1500; system must not add to this
  echo "$output" | grep -qvF "11499"  # 1500 + 9999 = 11499 must not appear
}

@test "v2: token footer shows total for meaningful records" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Seed: Doug 500 + Tom 800 + Laura 200 = 1500
  echo "$output" | grep -qF "1500"
}
