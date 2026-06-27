#!/usr/bin/env bash
# activity.sh — render the activity timeline as a self-contained HTML file.
# Reads all *.ndjson under $PL_RUNS (default $(pl_config_dir)/runs),
# sorts by .ts, and emits a chronological HTML table.
#
# Usage:
#   scripts/activity.sh [--out FILE] [--persona SLUG] [--since ISO8601_TS]
#
# Flags:
#   --out FILE        Write HTML to FILE instead of stdout
#   --persona SLUG    Filter to records where .persona == SLUG
#   --since TS        Filter to records where .ts >= TS (lexicographic ISO-8601 comparison)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

out="" filter_persona="" filter_since=""
while [ $# -gt 0 ]; do case "$1" in
  --out)     out="$2";            shift 2;;
  --persona) filter_persona="$2"; shift 2;;
  --since)   filter_since="$2";   shift 2;;
  *) pl_die "activity.sh: unknown arg $1";;
esac; done

runs="${PL_RUNS:-$(pl_config_dir)/runs}"

# Collect all ndjson files
files=()
if [ -d "$runs" ]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$runs" -maxdepth 1 -name '*.ndjson' -print0 2>/dev/null | sort -z)
fi

# Build jq filter expression for --persona / --since
jq_filter='.'
if [ -n "$filter_persona" ]; then
  jq_filter="${jq_filter} | select(.persona == \"${filter_persona}\")"
fi
if [ -n "$filter_since" ]; then
  jq_filter="${jq_filter} | select(.ts >= \"${filter_since}\")"
fi

# If no files, use empty input
if [ "${#files[@]}" -eq 0 ]; then
  records_json="[]"
else
  records_json="$(cat "${files[@]}" 2>/dev/null \
    | jq -s "[.[] | ${jq_filter}] | sort_by(.ts)")"
fi

# Generate HTML via jq — fully inline, no external deps except avatar CDN
html="$(printf '%s' "$records_json" | jq -r '
# -----------------------------------------------------------------------
# Helper: outcome → CSS colour token
def outcome_color:
  if . == "complete" or . == "posted" then "#22c55e"
  elif . == "error" then "#ef4444"
  else "#f59e0b"   # pending / acted / anything else → amber
  end;

def outcome_label:
  if . == "complete" then "complete"
  elif . == "posted"  then "posted"
  elif . == "error"   then "error"
  elif . == "acted"   then "acted"
  else .
  end;

# -----------------------------------------------------------------------
# Build avatar URL from persona slug (lowercase, strip spaces & accents)
def avatar_url:
  . as $slug |
  "https://cdn.jsdelivr.net/gh/ChristopherSchubert/persona-lab@main/assets/avatars/\($slug)/\($slug)-64.png";

def persona_slug:
  ascii_downcase | gsub("é"; "e") | gsub(" "; "");

# -----------------------------------------------------------------------
# Format timestamp: show date + time (UTC)
def fmt_ts:
  if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")
  then (.[0:10] + " " + .[11:19] + "Z")
  else .
  end;

# -----------------------------------------------------------------------
# Total tokens across all records
(map(.cost_tokens // 0) | add // 0) as $total_tokens |

# -----------------------------------------------------------------------
# HTML preamble
"<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"UTF-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>Persona Lab — Activity Timeline</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif;
    font-size: 14px;
    background: #0f172a;
    color: #e2e8f0;
    min-height: 100vh;
    padding: 24px;
  }
  h1 { font-size: 20px; font-weight: 700; margin-bottom: 20px; color: #f8fafc; letter-spacing: -0.01em; }
  h1 span { color: #64748b; font-weight: 400; font-size: 14px; margin-left: 8px; }
  table { width: 100%; border-collapse: collapse; }
  thead th {
    background: #1e293b;
    color: #94a3b8;
    font-weight: 600;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    padding: 10px 12px;
    border-bottom: 1px solid #334155;
    text-align: left;
    white-space: nowrap;
  }
  tr.row { border-bottom: 1px solid #1e293b; }
  tr.row:hover { background: #1e293b; }
  td { padding: 10px 12px; vertical-align: middle; }
  td.ts { color: #64748b; white-space: nowrap; font-variant-numeric: tabular-nums; font-size: 12px; }
  td.persona { white-space: nowrap; }
  .persona-inner { display: flex; align-items: center; gap: 8px; }
  .avatar {
    width: 28px; height: 28px; border-radius: 50%;
    object-fit: cover; flex-shrink: 0;
    background: #334155;
  }
  .persona-name { font-weight: 500; color: #f1f5f9; }
  td.action { color: #94a3b8; font-size: 12px; font-family: ui-monospace, SFMono-Regular, monospace; }
  .chip {
    display: inline-block; padding: 2px 8px; border-radius: 999px;
    font-size: 11px; font-weight: 600; color: #0f172a;
  }
  td.artifact a { color: #60a5fa; text-decoration: none; font-size: 12px; }
  td.artifact a:hover { text-decoration: underline; }
  td.tokens { text-align: right; color: #64748b; font-size: 12px; font-variant-numeric: tabular-nums; }
  tfoot td {
    padding: 12px;
    border-top: 2px solid #334155;
    color: #94a3b8;
    font-size: 12px;
  }
  tfoot .total-label { color: #64748b; }
  tfoot .total-value { color: #f1f5f9; font-weight: 600; font-variant-numeric: tabular-nums; }
  .empty { text-align: center; padding: 48px; color: #475569; }
</style>
</head>
<body>
<h1>Activity Timeline <span>" + (length | tostring) + " records</span></h1>
<table>
<thead>
  <tr>
    <th>Time (UTC)</th>
    <th>Persona</th>
    <th>Action</th>
    <th>Outcome</th>
    <th>Artifact</th>
    <th style=\"text-align:right\">Tokens</th>
  </tr>
</thead>
<tbody>",

# One row per record
(
  if length == 0 then
    "<tr><td colspan=\"6\" class=\"empty\">No activity records found.</td></tr>"
  else
    .[] |
    . as $rec |
    ($rec.persona // "") as $persona |
    ($persona | persona_slug) as $slug |
    ($slug | avatar_url) as $avatar |
    ($rec.outcome // "pending") as $outcome |
    ($outcome | outcome_color) as $color |
    ($outcome | outcome_label) as $label |
    ($rec.ts // "" | fmt_ts) as $ts |
    ($rec.action // $rec.trigger // "") as $action |
    ($rec.cost_tokens // 0) as $tok |
    (
      if ($rec.artifact_url != null and $rec.artifact_url != "") and ($rec.issue_number != null) then
        "<a href=\"" + $rec.artifact_url + "\">#" + ($rec.issue_number | tostring) + "</a>"
      elif ($rec.artifact_url != null and $rec.artifact_url != "") then
        "<a href=\"" + $rec.artifact_url + "\">" + $rec.artifact_url + "</a>"
      else ""
      end
    ) as $artifact_html |
    "<tr class=\"row\">
      <td class=\"ts\">" + $ts + "</td>
      <td class=\"persona\"><div class=\"persona-inner\"><img class=\"avatar\" src=\"" + $avatar + "\" alt=\"\" onerror=\"this.style.display=&#39;none&#39;\" loading=\"lazy\"><span class=\"persona-name\">" + $persona + "</span></div></td>
      <td class=\"action\">" + $action + "</td>
      <td><span class=\"chip\" style=\"background:" + $color + "\">" + $label + "</span></td>
      <td class=\"artifact\">" + $artifact_html + "</td>
      <td class=\"tokens\">" + ($tok | tostring) + "</td>
    </tr>"
  end
),

"</tbody>
<tfoot>
  <tr>
    <td colspan=\"5\" class=\"total-label\">Total tokens</td>
    <td class=\"tokens total-value\">" + ($total_tokens | tostring) + "</td>
  </tr>
</tfoot>
</table>
</body>
</html>"
')"

if [ -n "$out" ]; then
  printf '%s\n' "$html" > "$out"
else
  printf '%s\n' "$html"
fi
