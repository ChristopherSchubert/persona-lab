#!/usr/bin/env bash
# audit-sweep.sh — PROACTIVE discovery cycle (the "go hunt for work" counterpart to dispatch.sh).
#
# dispatch.sh is REACTIVE: it works issues that are already filed + labelled. But discovery roles
# (Technical Writer, Security, QA, Accessibility, Privacy, SRE, Design, Data Architect, FinOps,
# Delivery Manager) generate work by SWEEPING — they notice drift/gaps nobody filed. Their persona
# docs already promise a "scheduled" mode; this script is it.
#
# Usage:
#   scripts/audit-sweep.sh                 # sweep EVERY role in config/audit-roles.txt
#   scripts/audit-sweep.sh <persona-slug>  # sweep just that one role
#   scripts/audit-sweep.sh --dry-run       # list who would be swept; invoke nothing
#   [--repo o/r]                           # override the target repo
#
# Access model (issue #9): personas have no shell to file issues themselves. Each persona RETURNS
# its findings as a JSON array; the HARNESS files the NEW ones (duplicate titles are skipped) and
# records them. Findings are filed UNASSIGNED — no persona: label — because choosing the owner is
# triage's job (Sarah + the RACI), not the discoverer's. They ARE tagged `state:proposed` (#93/#129)
# so they land in the PM triage inbox automatically; the TRIAGE transition then routes for dispatch.
#
# Testability: the model is invoked via ${PL_CLAUDE:-claude}; tests stub it. NO real `claude` call
# happens in tests/dev.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

CLAUDE_BIN="${PL_CLAUDE:-claude}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"
roles_file="${PL_AUDIT_ROLES:-$here/../config/audit-roles.txt}"

# Colors for the chatty log — only when stderr is a real terminal and NO_COLOR is unset.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_HEAD=$'\033[1;36m'; C_DIM=$'\033[2m'; C_OK=$'\033[32m'; C_ERR=$'\033[1;31m'; C_WARN=$'\033[33m'; C_RST=$'\033[0m'
else
  C_HEAD=''; C_DIM=''; C_OK=''; C_ERR=''; C_WARN=''; C_RST=''
fi

dry_run=0; only=""
while [ $# -gt 0 ]; do case "$1" in
  --help|-h)  cat <<'HELP'
Usage: scripts/audit-sweep.sh [<persona-slug>] [--dry-run] [--repo owner/repo] [-v]

  <persona-slug>    Sweep only this role (e.g. qa-analyst, security-analyst)
  --dry-run         List who would be swept, invoke nothing
  --repo            Override target repo
  -v / --stream     Stream each persona's output live

Runs discovery personas against the repo to find new work and file issues.
Roles are listed in config/audit-roles.txt.
HELP
              exit 0;;
  --dry-run)      dry_run=1; shift;;
  --repo)         repo="$2"; shift 2;;
  --stream|-v)    PL_STREAM=1; shift;;
  -*)             pl_die "audit-sweep: unknown arg $1";;
  *)              only="$1"; shift;;
esac; done
PL_STREAM="${PL_STREAM:-0}"

# ── Resolve the role set ──────────────────────────────────────────────────────────────
roles=()
if [ -n "$only" ]; then
  [ -f "agents/$only.md" ] || pl_die "audit-sweep: no agent file agents/$only.md"
  roles=("$only")
else
  [ -f "$roles_file" ] || pl_die "audit-sweep: roles file not found: $roles_file"
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && roles+=("$line")
  done < "$roles_file"
fi
[ "${#roles[@]}" -gt 0 ] || { echo "audit-sweep: no roles to sweep" >&2; exit 0; }

if [ "$dry_run" -eq 1 ]; then
  for r in "${roles[@]}"; do
    echo "audit-sweep (dry-run): would sweep '${r}' ($("$here/assign-names.sh" "$r" 2>/dev/null || echo "$r")) on ${repo}"
  done
  exit 0
fi

# ── Helpers ───────────────────────────────────────────────────────────────────────────
_valid_rtype() { case "$1" in ASSESSMENT|DELIVERED|BLOCKER|REVIEW|PUSHBACK|FEEDBACK|ASK|REPLY) return 0;; *) return 1;; esac; }
# Extract one JSON value (object or array) from a persona's result text. Delegates to the shared,
# strengthened pl_extract_json in lib/common.sh (prefers the FINAL ```-fenced block, then LAST
# top-level value) so a quoted example never wins over the real findings array (#153).
_extract_json() { pl_extract_json; }

# Invoke a persona and echo its final result text. PL_STREAM=1 streams the turn LIVE to stderr
# (one line per tool call + text), so a run isn't a silent black box; default is buffered.
_run_claude() {
  local agent="$1" allowed="$2" prompt="$3"
  local model model_args
  model="$(pl_agent_model "$agent")"
  model_args="${model:+--model $model}"
  if [ "${PL_STREAM:-0}" = "1" ]; then
    local tmp; tmp="$(mktemp)"
    "$CLAUDE_BIN" -p "$prompt" --append-system-prompt-file "$agent" $model_args --allowedTools $allowed \
        --output-format stream-json --verbose 2>/dev/null | tee "$tmp" | while IFS= read -r ln; do
      printf '%s' "$ln" | jq -r --arg d "$C_DIM" --arg r "$C_RST" '
        if .type=="assistant" then (.message.content[]? |
            if .type=="tool_use" then "\($d)      · \(.name) \(.input.file_path // .input.pattern // .input.command // .input.path // "")\($r)"
            elif .type=="text" and ((.text|length)>0) then "\($d)      \(.text[0:200])\($r)"
            else empty end)
        else empty end' >&2 2>/dev/null
    done
    jq -r 'select(.type=="result") | .result // empty' "$tmp" 2>/dev/null | tail -1
    rm -f "$tmp"
  else
    local raw r
    raw="$("$CLAUDE_BIN" -p "$prompt" --append-system-prompt-file "$agent" $model_args --allowedTools $allowed --output-format json 2>/dev/null)"
    r="$(printf '%s' "$raw" | jq -r '.result // empty' 2>/dev/null)"
    [ -n "$r" ] && printf '%s' "$r" || printf '%s' "$raw"
  fi
}

# gh needs OWNER/REPO; the manifest's short `repo` would make `gh --repo` fail, so resolve it.
ghrepo="$(pl_gh_repo)"
# Existing OPEN issue titles, fetched once, for dedup so re-sweeps don't refile the same finding.
existing_titles="$(gh issue list --state open --json title --limit 300 | jq -r '.[].title')"

# ── Sweep one role: dispatch it to hunt, then file its new findings ────────────────────
sweep_one() {
  local persona="$1" agent="agents/$1.md"
  [ -f "$agent" ] || { echo "audit-sweep: no agent file $agent, skipping '$persona'" >&2; return; }
  local allowed name role
  allowed="$(awk -F': ' '/^tools:/{gsub(/, */," ",$2); print $2; exit}' "$agent")"
  [ -n "$allowed" ] || { echo "audit-sweep: '$persona' has no tools frontmatter, skipping" >&2; return; }
  name="$("$here/assign-names.sh" "$persona" 2>/dev/null || echo "$persona")"
  role="$(awk -F' — ' '/^# /{t=$1; sub(/^# +/,"",t); print t; exit}' "$agent")"

  # Build a specific, grounded prompt: recent changes + known failures + role focus.
  local recent_commits role_focus
  recent_commits="$(git log --oneline -15 2>/dev/null || echo '(unavailable)')"
  role_focus="$(awk '/^## Owns/{found=1; next} found && /^## /{exit} found{print}' "$agent" | head -20)"

  local prompt
  prompt="$(printf 'You are doing a targeted audit of repo %s. Your role focus:\n%s\n\nRecent changes (last 15 commits):\n%s\n\nOpen issues (do NOT re-file these):\n%s\n\nYour job: read the actual files relevant to your domain. Find concrete, specific, actionable problems — broken behaviour, missing coverage, gaps between what the code does and what it should do. Do NOT file vague observations. Each finding must cite the exact file:line or script output that proves the problem.\n\nYou CANNOT file issues directly — return findings and the harness files them. Emit findings as the FINAL ```json fenced block, nothing after it:\n```json\n[{"title":"<specific issue title>","body":"<what is broken, exact path:line evidence, why it matters, suggested fix>","record_type":"<ASSESSMENT|BLOCKER>","priority":"<p0|p1|p2|p3>"}]\n```\nReturn [] if you find nothing real.\n' "$repo" "$role_focus" "$recent_commits" "${existing_titles:-(none)}")"

  echo "${C_HEAD}audit-sweep: -> '${persona}' (${name} · ${role}) sweeping ${repo}...${C_RST}" >&2
  local result arr n filed=0 dup=0 i title body rtype prio url num
  result="$(_run_claude "$agent" "$allowed" "$prompt")"
  arr="$(printf '%s' "$result" | _extract_json || true)"
  if ! printf '%s' "$arr" | jq -e 'type=="array"' >/dev/null 2>&1; then
    if [ -z "$result" ]; then
      echo "${C_WARN}audit-sweep: <- '${persona}' returned nothing (claude produced no output)${C_RST}" >&2
    else
      echo "${C_WARN}audit-sweep: <- '${persona}' returned no parseable findings array — raw output below:${C_RST}" >&2
      printf '%s\n' "$result" | sed 's/^/    | /' | head -40 >&2
    fi
    arr="[]"
  fi
  n="$(printf '%s' "$arr" | jq 'length')"
  for ((i=0; i<n; i++)); do
    title="$(printf '%s' "$arr" | jq -r ".[$i].title // empty")"
    body="$(printf  '%s' "$arr" | jq -r ".[$i].body // empty")"
    rtype="$(printf '%s' "$arr" | jq -r ".[$i].record_type // \"ASSESSMENT\"")"
    prio="$(printf  '%s' "$arr" | jq -r ".[$i].priority // empty")"
    [ -n "$title" ] && [ -n "$body" ] || continue
    _valid_rtype "$rtype" || rtype="ASSESSMENT"
    if printf '%s\n' "$existing_titles" | grep -qxF "$title"; then dup=$((dup+1)); continue; fi
    if url="$("$here/queue.sh" file --persona "$name" --tier "$role" --type "$rtype" --title "$title" --body "$body" --repo "$ghrepo" 2>&1)"; then
      :
    else
      echo "${C_ERR}audit-sweep:    FILE FAILED for '${title}':${C_RST}" >&2
      printf '%s\n' "$url" | sed 's/^/        /' >&2
      url=""; continue
    fi
    num="${url##*/}"
    # Route the finding into the PM triage inbox (#93/#129, Sarah's DECISION): every filed finding
    # carries `state:proposed` — the one binding "untriaged, awaiting PM" signal the PM sweeps. The
    # model's `priority:` below stays as a provisional hint, re-confirmed/overridden at TRIAGE.
    [ -n "$num" ] && "$here/queue.sh" label "$num" --add "state:proposed" --repo "$ghrepo" >/dev/null 2>&1 || true
    case "$prio" in p0|p1|p2|p3) [ -n "$num" ] && "$here/queue.sh" label "$num" --add "priority:$prio" --repo "$ghrepo" >/dev/null 2>&1 || true;; esac
    existing_titles="$(printf '%s\n%s' "$existing_titles" "$title")"   # also dedup within this run
    filed=$((filed+1))
    echo "${C_OK}audit-sweep:    filed #${num} [${prio:-p?}] ${title}${C_RST}" >&2
  done
  echo "${C_HEAD}audit-sweep: <- '${persona}': ${n} finding(s), ${filed} filed, ${dup} duplicate(s) skipped${C_RST}" >&2
  "$here/runlog.sh" append --persona "$persona" --repo "$repo" --trigger "audit-sweep" \
    --outcome "swept" --record-type "audit" --action "sweep" || true
}

for r in "${roles[@]}"; do sweep_one "$r"; done
exit 0

# ──────────────────────────────────────────────────────────────────────────────────────
# CADENCE (left OFF by design): this runs one sweep and stops. Point an external scheduler at
# it for periodic discovery, e.g. once a day so audits don't spam the bus:
#   cron: 0 9 * * * cd /path/to/persona-lab && scripts/audit-sweep.sh >> audit.log 2>&1
# Keep PL_CLAUDE unset in production; set it to a stub in tests/dev so no paid call is made.
