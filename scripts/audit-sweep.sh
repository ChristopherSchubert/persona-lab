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
# records them. Findings are filed UNROUTED — no persona: label — because choosing the owner is
# triage's job (Sarah + the RACI), not the discoverer's. So a sweep surfaces work into the queue;
# triage then routes it for dispatch.
#
# Testability: the model is invoked via ${PL_CLAUDE:-claude}; tests stub it. NO real `claude` call
# happens in tests/dev.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

CLAUDE_BIN="${PL_CLAUDE:-claude}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"
roles_file="${PL_AUDIT_ROLES:-$here/../config/audit-roles.txt}"

dry_run=0; only=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) dry_run=1; shift;;
  --repo)    repo="$2"; shift 2;;
  -*)        pl_die "audit-sweep: unknown arg $1";;
  *)         only="$1"; shift;;
esac; done

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
# Best-effort extract one JSON value (object or array) from a persona's result text.
_extract_json() {
  local in; in="$(cat)"
  printf '%s' "$in" | jq -ce . 2>/dev/null && return 0
  printf '%s' "$in" | awk '/^```/{f=!f; next} {print}' | jq -ce . 2>/dev/null && return 0
  return 1
}

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

  local prompt
  prompt="$(printf 'You are sweeping repo %s for work in YOUR domain that is NOT yet tracked as an open issue. Audit the committed state (code, docs, tests, config) with your granted tools. You CANNOT file issues — return findings and the harness files the new ones (duplicate titles are skipped). Return ONLY a JSON array (empty [] if nothing), each item exactly:\n{"title":"<concise issue title>","body":"<the finding as GitHub-flavored markdown: what, where as path:line, why it matters>","record_type":"<ASSESSMENT|BLOCKER>","priority":"<p0|p1|p2|p3>"}\n' "$repo")"

  echo "audit-sweep: -> '${persona}' (${name} · ${role}) sweeping ${repo}..." >&2
  local raw result arr n filed=0 dup=0 i title body rtype prio url num
  if ! raw="$("$CLAUDE_BIN" -p "$prompt" --append-system-prompt-file "$agent" --allowedTools $allowed --output-format json 2>/dev/null)"; then
    echo "audit-sweep: <- '${persona}' claude invocation FAILED" >&2; return
  fi
  result="$(printf '%s' "$raw" | jq -r '.result // empty' 2>/dev/null)"; [ -n "$result" ] || result="$raw"
  arr="$(printf '%s' "$result" | _extract_json || true)"
  if ! printf '%s' "$arr" | jq -e 'type=="array"' >/dev/null 2>&1; then
    echo "audit-sweep: <- '${persona}' returned no findings array" >&2; arr="[]"
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
    if ! url="$("$here/queue.sh" file --persona "$name" --tier "$role" --type "$rtype" --title "$title" --body "$body" --repo "$repo" 2>/dev/null)"; then
      echo "audit-sweep:    FILE FAILED: ${title}" >&2; continue
    fi
    num="${url##*/}"
    case "$prio" in p0|p1|p2|p3) [ -n "$num" ] && "$here/queue.sh" label "$num" --add "priority:$prio" --repo "$repo" >/dev/null 2>&1 || true;; esac
    existing_titles="$(printf '%s\n%s' "$existing_titles" "$title")"   # also dedup within this run
    filed=$((filed+1))
    echo "audit-sweep:    filed #${num} [${prio:-p?}] ${title}" >&2
  done
  echo "audit-sweep: <- '${persona}': ${n} finding(s), ${filed} filed, ${dup} duplicate(s) skipped" >&2
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
