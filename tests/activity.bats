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
  [[ "$output" == *"<html"* ]]
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
  [[ "$output" == *"cdn.jsdelivr.net/gh/ChristopherSchubert/persona-lab@main/assets/avatars/"* ]]
}

@test "activity: avatar img has onerror hide" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"onerror"* ]]
}

@test "activity: HTML contains artifact link for records with issue_number" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # Issues 10 and 11 should produce linked #N anchors
  [[ "$output" == *"#10"* ]]
  [[ "$output" == *"#11"* ]]
}

@test "activity: artifact link href uses artifact_url" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/o/r/issues/10"* ]]
}

@test "activity: token footer sums all cost_tokens" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # 500 + 800 + 200 = 1500
  [[ "$output" == *"1500"* ]]
}

@test "activity: outcome color chips present" {
  run scripts/activity.sh
  [ "$status" -eq 0 ]
  # acted / pending → amber, complete → green, error → red
  [[ "$output" == *"amber"* || "$output" == *"#f59e0b"* || "$output" == *"pending"* ]]
  [[ "$output" == *"green"* || "$output" == *"#22c55e"* || "$output" == *"complete"* ]]
  [[ "$output" == *"red"* || "$output" == *"#ef4444"* || "$output" == *"error"* ]]
}

@test "activity: --persona filter limits output rows" {
  run scripts/activity.sh --persona Doug
  [ "$status" -eq 0 ]
  count="$(echo "$output" | grep -c '<tr class="row')"
  [ "$count" -eq 1 ]
  [[ "$output" == *"Doug"* ]]
  [[ "$output" != *"Tom"* ]]
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
  [[ "$output" != *"bootstrap"* ]]
  [[ "$output" != *"tailwind"* ]]
  [[ "$output" != *"react"* ]]
  [[ "$output" != *"<script src"* ]]
  [[ "$output" != *'<link rel="stylesheet"'* ]]
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
