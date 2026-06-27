#!/usr/bin/env bash
# activity.sh — render the activity timeline as a self-contained HTML file.
# v2: noise suppression, plain-English sentences, issue grouping.
# Reads all *.ndjson under $PL_RUNS (default $(pl_config_dir)/runs),
# sorts by .ts, and emits a grouped HTML timeline.
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

# Build jq filter expression for --persona / --since.
# Values are passed via --arg so they are never interpolated into jq source code.
jq_filter='.'
jq_args=()
if [ -n "$filter_persona" ]; then
  jq_filter="${jq_filter} | select(.persona == \$filter_persona)"
  jq_args+=(--arg filter_persona "$filter_persona")
fi
if [ -n "$filter_since" ]; then
  jq_filter="${jq_filter} | select(.ts >= \$filter_since)"
  jq_args+=(--arg filter_since "$filter_since")
fi

# If no files, use empty input
if [ "${#files[@]}" -eq 0 ]; then
  records_json="[]"
else
  records_json="$(cat "${files[@]}" 2>/dev/null \
    | jq -s "${jq_args[@]+"${jq_args[@]}"}" "[.[] | ${jq_filter}] | sort_by(.ts)")"
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
# Suppression predicate (Laura v2 spec):
# Keep a record only when all three hold:
#   1. persona != "system"
#   2. action != "bus:quarantine"
#   3. NOT (cost_tokens==0 AND action=="bus:comment" AND role is blank/absent)
def is_meaningful:
  .persona != "system"
  and .action != "bus:quarantine"
  and ((.cost_tokens == 0 and .action == "bus:comment" and ((.role // "") == "")) | not);

# -----------------------------------------------------------------------
# Action → plain-English sentence fragment.
# Returns the verb+object string (persona name is prepended by the caller).
# Outcome is used for summon-with-no-action disambiguation.
def action_sentence($action; $trigger; $outcome; $issue_number; $artifact_url; $url_is_safe):
  if $action == "bus:comment" then
    if $issue_number != null then
      "commented on issue " +
      if ($url_is_safe and ($issue_number != null)) then
        "<a href=\"" + ($artifact_url | @html) + "\">#" + ($issue_number | tostring | @html) + "</a>"
      else
        "#" + ($issue_number | tostring | @html)
      end
    else
      "commented"
    end
  elif $action == "bus:park" then
    "parked issue " +
    if ($url_is_safe and ($issue_number != null)) then
      "<a href=\"" + ($artifact_url | @html) + "\">#" + ($issue_number | tostring | @html) + "</a>"
    else
      "#" + ($issue_number | tostring | @html)
    end + " for later"
  elif $action == "build" then
    "ran a build"
  elif ($action == "" or $action == null) and $trigger == "summon" then
    if $outcome == "error" then "encountered an error"
    elif $outcome == "complete" then "completed work"
    else "picked up work"
    end
  else
    # Unknown code: render in <code> so the gap surfaces, but row still shows
    "performed <code>" + ($action | @html) + "</code>"
  end;

# -----------------------------------------------------------------------
# Outcome note: appended after em-dash only when it adds info
def outcome_note($outcome; $action):
  if $outcome == "error" then " — failed"
  elif $outcome == "acted" then " — further action needed"
  elif $outcome == "pending" then " — in progress"
  elif $outcome == "complete" and ($action != "bus:comment" and $action != "build") then ""
  else ""
  end;

# -----------------------------------------------------------------------
# Render a single timeline row (either primary or suppressed)
def render_row($rec; $row_class):
  ($rec.persona // "") as $persona |
  ($persona | persona_slug) as $slug |
  ($slug | avatar_url) as $avatar |
  ($rec.outcome // "pending") as $outcome |
  ($outcome | outcome_color) as $color |
  ($outcome | outcome_label) as $label |
  ($rec.ts // "" | fmt_ts) as $ts |
  ($rec.action // "") as $action |
  ($rec.trigger // "") as $trigger |
  ($rec.role // "") as $role |
  ($rec.issue_number) as $issue_number |
  ($rec.artifact_url // "") as $raw_artifact_url |
  ($raw_artifact_url | startswith("https://")) as $url_is_safe |
  ($avatar | @html) as $safe_avatar |
  ($persona | @html) as $safe_persona |
  ($ts | @html) as $safe_ts |
  ($label | @html) as $safe_label |
  ($role | @html) as $safe_role |
  # First letter of persona name for initials fallback
  (if ($persona | length) > 0 then $persona[0:1] | ascii_upcase else "?" end) as $initial |
  action_sentence($action; $trigger; $outcome; $issue_number; $raw_artifact_url; $url_is_safe) as $sentence |
  outcome_note($outcome; $action) as $note |
  "<tr class=\"\($row_class)\">
    <td class=\"ts\">\($safe_ts)</td>
    <td class=\"persona\">
      <div class=\"persona-inner\">
        <span class=\"avatar-wrap\">
          <img class=\"avatar\" src=\"\($safe_avatar)\" alt=\"\" onerror=\"this.parentElement.classList.add(&#39;img-err&#39;)\" loading=\"lazy\">
          <span class=\"avatar-initials\" aria-hidden=\"true\">\($initial)</span>
        </span>
        <div>
          <span class=\"persona-name\">\($safe_persona)</span>
          <span class=\"sentence\"> \($sentence)\($note)</span>
          \(if $safe_role != "" then "<span class=\"persona-role\">\($safe_role)</span>" else "" end)
        </div>
      </div>
    </td>
    <td><span class=\"chip\" style=\"background:\($color)\">\($safe_label)</span></td>
  </tr>";

# -----------------------------------------------------------------------
# Split into meaningful and suppressed
. as $all |
[ .[] | select(is_meaningful) ] as $meaningful |
[ .[] | select(is_meaningful | not) ] as $suppressed |
($meaningful | length) as $m_count |
($all | length) as $total_count |
($meaningful | map(.cost_tokens // 0) | add // 0) as $total_tokens |

# Group meaningful records by issue_number (null → Infrastructure)
($meaningful | group_by(.issue_number)) as $groups |

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
  .issue-card {
    margin-bottom: 24px;
    border: 1px solid #1e293b;
    border-radius: 8px;
    overflow: hidden;
  }
  .issue-heading {
    background: #1e293b;
    padding: 10px 16px;
    font-size: 13px;
    font-weight: 600;
    color: #94a3b8;
    border-bottom: 1px solid #334155;
  }
  .issue-heading a { color: #60a5fa; text-decoration: none; }
  .issue-heading a:hover { text-decoration: underline; }
  .issue-heading .issue-label { color: #64748b; font-weight: 400; margin-left: 6px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; }
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
  .avatar-wrap {
    position: relative; width: 28px; height: 28px; flex-shrink: 0;
  }
  .avatar {
    width: 28px; height: 28px; border-radius: 50%;
    object-fit: cover;
    background: #334155;
  }
  .avatar-initials {
    position: absolute; inset: 0;
    display: none;
    align-items: center; justify-content: center;
    border-radius: 50%;
    background: #334155;
    color: #94a3b8;
    font-size: 12px; font-weight: 700;
    line-height: 1;
    pointer-events: none;
  }
  /* When onerror adds .img-err to .avatar-wrap, hide img and show initials */
  .avatar-wrap.img-err .avatar { visibility: hidden; }
  .avatar-wrap.img-err .avatar-initials { display: flex; }
  .persona-name { font-weight: 500; color: #f1f5f9; }
  .sentence { color: #cbd5e1; }
  .sentence a { color: #60a5fa; text-decoration: none; }
  .sentence a:hover { text-decoration: underline; }
  .sentence code { font-family: ui-monospace, SFMono-Regular, monospace; background: #1e293b; padding: 1px 4px; border-radius: 3px; font-size: 11px; color: #fbbf24; }
  .persona-role { display: block; color: #64748b; font-size: 11px; margin-top: 2px; }
  .chip {
    display: inline-block; padding: 2px 8px; border-radius: 999px;
    font-size: 11px; font-weight: 600; color: #0f172a;
  }
  tfoot td {
    padding: 12px;
    border-top: 2px solid #334155;
    color: #94a3b8;
    font-size: 12px;
  }
  tfoot .total-label { color: #64748b; }
  tfoot .total-value { color: #f1f5f9; font-weight: 600; font-variant-numeric: tabular-nums; }
  .empty { text-align: center; padding: 48px; color: #475569; }
  /* Show-all toggle — CSS only, no JS */
  details { margin-top: 32px; }
  details summary {
    cursor: pointer;
    color: #64748b;
    font-size: 12px;
    padding: 8px 0;
    user-select: none;
    list-style: none;
  }
  details summary::before { content: \"▶  \"; font-size: 10px; }
  details[open] summary::before { content: \"▼  \"; }
  details summary::-webkit-details-marker { display: none; }
  tr.row.suppressed td { color: #475569; font-style: italic; opacity: 0.6; }
  tr.row.suppressed .persona-name { color: #475569; }
  tr.row.suppressed .chip { opacity: 0.5; }
  .infra-heading {
    background: #0f172a;
    padding: 10px 16px;
    font-size: 12px;
    font-weight: 600;
    color: #64748b;
    border-bottom: 1px solid #1e293b;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }
</style>
</head>
<body>
<h1>Activity Timeline <span>" + ($m_count | tostring) + " events (" + ($total_count | tostring) + " total)</span></h1>",

# -----------------------------------------------------------------------
# Primary content — grouped by issue
(
  if $m_count == 0 then
    "<p class=\"empty\">No meaningful activity records found.</p>"
  else
    # Separate issue groups from non-issue records
    [ $groups[] | select(.[0].issue_number != null) ] as $issue_groups |
    [ $meaningful[] | select(.issue_number == null) ] as $infra_records |

    # Render each issue card (one card per distinct issue_number)
    (
      $issue_groups[] |
      . as $group |
      ($group[0].issue_number) as $inum |
      ($group[0].artifact_url // "") as $issue_url |
      ($issue_url | startswith("https://")) as $issue_url_safe |
      "<div class=\"issue-card\"><div class=\"issue-heading\">" +
      (if $issue_url_safe then
        "<a href=\"" + ($issue_url | @html) + "\">#" + ($inum | tostring | @html) + "</a>"
      else
        "#" + ($inum | tostring | @html)
      end) +
      "<span class=\"issue-label\">issue</span></div>" +
      "<table><tbody>" +
      ($group | map(render_row(.; "row")) | join("")) +
      "</tbody></table></div>"
    ),

    # Infrastructure section (no issue_number) — one card for all infra records
    (
      if ($infra_records | length) > 0 then
        "<div class=\"issue-card\"><div class=\"infra-heading\">Infrastructure</div>" +
        "<table><tbody>" +
        ($infra_records | map(render_row(.; "row")) | join("")) +
        "</tbody></table></div>"
      else ""
      end
    )
  end
),

# Token footer (meaningful records only)
"<table style=\"margin-top:16px\"><tfoot><tr>
  <td colspan=\"3\" class=\"total-label\">Total tokens (meaningful events)</td>
  <td class=\"ts total-value\">" + ($total_tokens | tostring) + "</td>
</tr></tfoot></table>",

# -----------------------------------------------------------------------
# Show-all toggle — CSS/details, no JS dependency
(
  if ($suppressed | length) > 0 then
    "<details><summary>Show all " + ($total_count | tostring) + " records (includes " + (($suppressed | length) | tostring) + " suppressed)</summary>" +
    "<div class=\"issue-card\" style=\"margin-top:12px\"><table><thead><tr>" +
    "<th>Time (UTC)</th><th>Persona / Action</th><th>Outcome</th>" +
    "</tr></thead><tbody>" +
    ($suppressed | map(render_row(.; "row suppressed")) | join("")) +
    "</tbody></table></div></details>"
  else ""
  end
),

"</body>
</html>"
')"

if [ -n "$out" ]; then
  printf '%s\n' "$html" > "$out"
else
  printf '%s\n' "$html"
fi
