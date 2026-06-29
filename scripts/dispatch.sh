#!/usr/bin/env bash
# dispatch.sh — ONE dispatch cycle (issue #45, "personas operate the bus").
#
# Autonomy model (Tom's PROPOSAL/DECISION on #45, superseding Sarah's one-per-cycle for
# readers only): a cycle dispatches TWO independent partitions, classified by the existing
# is_writer_persona():
#   - reader/consultant issues (is_writer_persona=false): up to PL_READONLY_CAP (default 1)
#     dispatched CONCURRENTLY as background jobs, NO writer lock. Clamped by a hard ceiling
#     PL_READONLY_HARD_CAP (default 8) so an accidental large cap can't spawn unbounded work.
#   - writer issue (is_writer_persona=true): at most ONE per cycle, foreground, writer lock
#     required — unchanged from the original one-per-cycle model.
# Both partitions run in the SAME cycle; the script `wait`s for all background readers
# before exiting, so the run-log is complete before the next scheduler trigger.
#
# Reversible default: PL_READONLY_CAP=1 → identical behaviour to the prior single-dispatch
# model (one reader OR one writer). No autonomy-posture change ships on by default; the
# founder raises PL_READONLY_CAP to open it. The writer-lock CAS in lock.sh is UNCHANGED —
# this is purely a selection-loop extension.
#
# The schedule itself stays OFF — nothing here installs cron/launchd/hooks. To enable a
# recurring sweep, wire an external scheduler to run this script (see the note at the
# bottom of this file and the README).
#
# Dispatchable = open issue that is READY and has an assigned persona:
#   - ready signal:   carries `state:ready` (ADR-0001 `ready` state) ...
#   - persona signal: carries exactly one `persona:<slug>` label (this file defines the
#                     convention; <slug> is an agents/<slug>.md persona)
#   - not blocked:    no `blocked-by:*`, `needs-human:*`, or `quarantine` label
#   - dev:ready gate (#37): the WRITER (developer) partition additionally requires a
#                     `dev:ready` label — `state:ready` alone means upstream review/design/
#                     acceptance isn't done. Readers/consultants are UNCHANGED (dispatch on
#                     `state:ready` alone). This is a pre-selection filter only; the
#                     writer-lock invariant in lock.sh is untouched.
# Highest = lowest priority number (priority:p0 > p1 > p2 > p3; default p3), ties broken
# by oldest issue number.
#
# An issue that is ready+unblocked but carries no `persona:` label is SKIPPED (and the
# reason logged) — dispatch never guesses an owner.
#
# Testability: the model is invoked via ${PL_CLAUDE:-claude}; tests stub it. NO real
# `claude` call happens in tests/dev. lock.sh is reachable via ${PL_LOCK_SH} for stubbing.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

dry_run=0
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) dry_run=1; shift;;
  *) pl_die "dispatch: unknown arg $1";;
esac; done

CLAUDE_BIN="${PL_CLAUDE:-claude}"
LOCK_SH="${PL_LOCK_SH:-$here/lock.sh}"
repo="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo unknown)}"
ghrepo="$(pl_gh_repo)"   # gh-valid OWNER/REPO for bus posts (manifest 'repo' may be a short name)

# A MUTATOR holds the writer lock before dispatch: any persona granted Write/Edit — the
# Developer (`writes`, the code writer) OR a doc-writer (`doc-writes`). At most ONE mutator
# runs per cycle (foreground, locked) so concurrent edits can't clobber the shared working
# tree. Capacity is read from the agent's `tools:` frontmatter (built from capability-map.json),
# so this needs no hardcoded persona list — add a role to doc-writers and it serializes too.
_agent_tools() { awk -F'tools:[[:space:]]*' '/^tools:/{print $2; exit}' "agents/$1.md" 2>/dev/null; }
is_mutating_persona() { case "$(_agent_tools "$1")" in *Write*|*Edit*) return 0;; *) return 1;; esac; }
# The code writer (Write+Bash = Developer) is additionally gated on `dev:ready`; doc-writers are
# not — a doc edit doesn't require upstream code review/design to be done.
is_code_writer() { local t; t="$(_agent_tools "$1")"; case "$t" in *Bash*) case "$t" in *Write*) return 0;; esac;; esac; return 1; }

# Caps (reversible defaults). PL_READONLY_CAP=1 reproduces the old one-per-cycle model.
# PL_READONLY_HARD_CAP is a safety rail: the effective reader cap is never larger than it,
# regardless of PL_READONLY_CAP, so a stray big value can't fan out unbounded model calls.
readonly_cap="${PL_READONLY_CAP:-1}"
hard_cap="${PL_READONLY_HARD_CAP:-8}"
case "$readonly_cap" in ''|*[!0-9]*) pl_die "dispatch: PL_READONLY_CAP must be a non-negative integer";; esac
case "$hard_cap"     in ''|*[!0-9]*) pl_die "dispatch: PL_READONLY_HARD_CAP must be a non-negative integer";; esac
[ "$readonly_cap" -le "$hard_cap" ] && eff_cap="$readonly_cap" || eff_cap="$hard_cap"

# ── Select dispatchable issues, partitioned by capacity ───────────────────────────────
# Pull open issues with number + labels, then rank in jq:
#   keep:  has state:ready AND a persona:* label AND no blocking label
#   sort:  priority asc (p0=0 … p3=3, default 3), then number asc
#   emit:  every candidate as "<number>\t<persona-slug>\t<dev_ready>", highest-priority first.
# `dev_ready` is "1" iff the issue also carries `dev:ready` (Tom's design on #37): the
# code writer requires it; doc-writers and readers ignore it.
# Partitioning into mutator vs reader is done in bash via is_mutating_persona() (capacity read
# from the agent tools), so the one boundary stays the source of truth (no persona list in jq).
issues_json="$(gh issue list --state open --json number,labels --limit 200)"

candidates="$(printf '%s' "$issues_json" | jq -r '
  def labelset: [.labels[].name];
  def prio:
    (labelset | map(select(startswith("priority:p"))) | .[0] // "priority:p3"
     | ltrimstr("priority:p") | tonumber? // 3);
  def persona:
    (labelset | map(select(startswith("persona:"))) | .[0] // "" | ltrimstr("persona:"));
  def blocked:
    (labelset | any(.[]; startswith("blocked-by:") or startswith("needs-human:") or . == "quarantine"));
  def dev_ready:
    (labelset | any(.[]; . == "dev:ready"));
  [ .[]
    | select(labelset | any(.[]; . == "state:ready"))
    | select(blocked | not)
    | select(persona != "")
    | {number, persona: persona, prio: prio, dev_ready: (if dev_ready then 1 else 0 end)}
  ]
  | sort_by(.prio, .number)
  | .[]
  | "\(.number)\t\(.persona)\t\(.dev_ready)"
')"

# Partition into ONE mutator (Write/Edit — serialized on the lock) and readers (up to eff_cap),
# preserving the priority order from jq. The first eligible mutator fills the single locked slot.
# DEV:READY GATE (#37): a *code writer* candidate is eligible only if it carries `dev:ready`
# (dr=1) — `state:ready` alone means upstream work isn't done. Doc-writers serialize too but are
# NOT dev:ready-gated. Readers are never gated; they dispatch on `state:ready` as before.
writer_line=""
reader_lines=()
if [ -n "$candidates" ]; then
  while IFS=$'\t' read -r num pers dr; do
    [ -n "$num" ] || continue
    if is_mutating_persona "$pers"; then
      if [ -z "$writer_line" ]; then
        if is_code_writer "$pers"; then
          [ "$dr" = "1" ] && writer_line="${num}"$'\t'"${pers}"   # code writer needs dev:ready
        else
          writer_line="${num}"$'\t'"${pers}"                      # doc-writer: serialized, no gate
        fi
      fi
    else
      if [ "${#reader_lines[@]}" -lt "$eff_cap" ]; then
        reader_lines+=("${num}"$'\t'"${pers}")
      fi
    fi
  done <<< "$candidates"
fi

# Nothing dispatchable? Distinguish "nothing" from "ready but persona-less" for the skip log.
if [ -z "$writer_line" ] && [ "${#reader_lines[@]}" -eq 0 ]; then
  skipped="$(printf '%s' "$issues_json" | jq -r '
    def labelset: [.labels[].name];
    def blocked:
      (labelset | any(.[]; startswith("blocked-by:") or startswith("needs-human:") or . == "quarantine"));
    [ .[]
      | select(labelset | any(.[]; . == "state:ready"))
      | select(blocked | not)
      | select(labelset | any(.[]; startswith("persona:")) | not)
      | .number ] | join(" ")')"
  if [ -n "$skipped" ]; then
    echo "dispatch: skipping ready issue(s) with no persona: label (no owner to dispatch): $skipped" >&2
  fi
  echo "dispatch: nothing ready to dispatch" >&2
  exit 0
fi

if [ "$dry_run" -eq 1 ]; then
  for line in ${reader_lines[@]+"${reader_lines[@]}"}; do
    rn="${line%%$'\t'*}"; rp="${line#*$'\t'}"
    echo "dispatch (dry-run): would dispatch reader issue #${rn} to persona '${rp}' via ${CLAUDE_BIN} -p (persona system prompt, capacity-scoped tools, harness posts record; no lock)"
  done
  if [ -n "$writer_line" ]; then
    wn="${writer_line%%$'\t'*}"; wp="${writer_line#*$'\t'}"
    echo "dispatch (dry-run): would dispatch writer issue #${wn} to persona '${wp}' via ${CLAUDE_BIN} -p (persona system prompt, capacity-scoped tools, harness posts record; writer lock)"
  fi
  exit 0
fi

# ── Dispatch one unit of work, capture the outcome, write its run record ───────────────
# Self-contained so it can run in the background (readers) or foreground (writer). Lock
# handling stays in the caller: this function never touches the writer lock.
# Valid record-type vocabulary (grounded rename). The harness rejects anything else so a
# malformed persona response never lands a junk envelope on the bus.
_valid_rtype() { case "$1" in
  ASSESSMENT|DELIVERED|BLOCKER|REVIEW|PUSHBACK|FEEDBACK|ASK|REPLY) return 0;; *) return 1;;
esac; }

# Drive the ADR-0001 state machine FORWARD after a record lands (issue #132 — the treadmill
# fix). Before this, dispatch_one posted a record but left `state:ready` on the issue, so the
# next cycle re-selected the SAME issue forever and lower items starved. Personas can't fix
# this — they have no shell. The harness (which does) is the only place the transition can be
# applied, so it maps the record type to the next sub-state (#37: in_progress/in_review/parked)
# and, critically, REMOVES `state:ready` so the issue leaves the Act queue.
#
# Mapping (record type → next state), per the ADR-0001 transition table:
#   DELIVERED  → in_review   (SUBMIT: hand to the Greg/Priya review gates)
#   BLOCKER    → parked      (PARK:   blocked; owner/deadline live in the record body)
#   ASK        → parked      (ASK parks the issue while it waits on input)
#   else       → in_progress (worked, not yet delivered; off the queue pending the next step)
# Removing `state:ready` is the load-bearing half: selection requires it, so a worked issue
# can't be re-picked. A persona needing another turn does NOT silently stay ready — the PM
# (or a RESUME) must re-ready it, so multi-turn work is explicit, not accidental.
advance_state() {
  local n="$1" rt="$2" next
  case "$rt" in
    DELIVERED|REVIEW) next="state:in_review";;
    BLOCKER|ASK)      next="state:parked";;
    *)                next="state:in_progress";;
  esac
  # One atomic edit sets the next state AND drops state:ready — if this fails the issue stays
  # ready (re-selectable) rather than floating with no state, and we log loudly. dev:ready is
  # cleaned up best-effort afterwards: it's inert once state:ready is gone (selection needs
  # state:ready), so a stray dev:ready can't resurrect the treadmill.
  if gh issue edit "$n" --repo "$ghrepo" --add-label "$next" --remove-label "state:ready" >/dev/null 2>&1; then
    echo "dispatch: state #${n} -> ${next} (left state:ready) [${rt}]" >&2
    gh issue edit "$n" --repo "$ghrepo" --remove-label "dev:ready" >/dev/null 2>&1 || true
  else
    echo "dispatch: WARNING #${n} state advance FAILED — stays state:ready, will re-select [${rt}]" >&2
  fi
}

# Extract one JSON object from a persona's result text. Delegates to the shared, strengthened
# pl_extract_json in lib/common.sh (prefers the FINAL ```-fenced block, then LAST top-level value)
# so a JSON example in the prose can never be grabbed ahead of the real record (#153).
_extract_json() { pl_extract_json; }

# Dispatch one unit of work and POST THE PERSONA'S RECORD on its behalf.
# Why the harness posts (issue #9 access-model fix): most personas are read-only (Read,Grep,Glob)
# and have no shell, so they cannot run scripts/queue.sh themselves. Instead each persona RETURNS
# one record as JSON; the harness (which has the shell) posts it under the persona envelope. This
# also rescues reader output, which the background dispatch would otherwise drop to /dev/null.
dispatch_one() {
  local issue_number="$1" persona="$2" agent="agents/$2.md" outcome="failed"
  # Capacity enforced at the invocation: the agent file is the system prompt, and --allowedTools
  # comes from its `tools:` frontmatter (capacity-derived). In -p mode any tool not listed is
  # denied — so a reads-capacity persona cannot Edit/Write *and cannot run a shell to post*.
  local allowed name role
  allowed="$(awk -F': ' '/^tools:/{gsub(/, */," ",$2); print $2; exit}' "$agent")"
  [ -n "$allowed" ] || pl_die "dispatch: no 'tools:' frontmatter in $agent"
  name="$("$here/assign-names.sh" "$persona" 2>/dev/null || echo "$persona")"   # slug -> display name (envelope + avatar)
  role="$(awk -F' — ' '/^# /{t=$1; sub(/^# +/,"",t); print t; exit}' "$agent")" # role title from the agent H1

  # Read the bus FOR the persona (it usually can't): inject the issue's title/body/comments so it
  # operates on the REAL task instead of just "issue #N" (#125).
  local issue_ctx; issue_ctx="$(pl_issue_context "$issue_number" "$ghrepo")"
  local prompt
  prompt="$(printf '%s\n\n---\n\nYou are operating the issue above (#%s) on repo %s. Do ONE bounded unit of work for your role (ADR-0001), using only the tools you have been granted. Act on the issue body/discussion above. You do NOT post to the bus — the harness posts your record for you. End your turn by emitting your record as the FINAL ```json fenced code block in your message, with NOTHING after the closing fence. The block must contain exactly one JSON object (if your prose quotes any other JSON, the harness still takes only this last fenced block):\n```json\n{"record_type":"<ASSESSMENT|DELIVERED|BLOCKER|REVIEW|PUSHBACK|FEEDBACK|ASK|REPLY>","body":"<your record as GitHub-flavored markdown; if you changed code or opened a PR, cite it>"}\n```\nIf and only if you are REVIEWING a pull request, the JSON object in that final fenced block must instead be:\n{"record_type":"REVIEW","pr":<the PR number>,"verdict":"<approve|request-changes|comment>","body":"<your review as markdown, citing the commit>"}\nThe harness posts this as a real PR review (gh pr review) so the merge gate can see your verdict.\n' "$issue_ctx" "$issue_number" "$repo")"

  echo "dispatch: -> #${issue_number} '${persona}' (${name} · ${role}) [allowedTools: ${allowed}]" >&2
  local raw result record rtype body pr verdict url=""
  if raw="$("$CLAUDE_BIN" -p "$prompt" --append-system-prompt-file "$agent" --allowedTools $allowed --output-format json 2>/dev/null)"; then
    result="$(printf '%s' "$raw" | jq -r '.result // empty' 2>/dev/null)"
    [ -n "$result" ] || result="$raw"        # tolerate non-envelope output (stubs / --output-format text)
    record="$(printf '%s' "$result" | _extract_json || true)"
    rtype="$(printf '%s' "$record" | jq -r '.record_type // empty' 2>/dev/null)"
    body="$(printf '%s'  "$record" | jq -r '.body // empty'        2>/dev/null)"
    # #195: a REVIEW record that names a `pr` is a verdict ON that PR — it must land as a real
    # `gh pr review` (so GitHub's review state is set and the merge gate can see it), not as an
    # issue comment. `verdict` is the reviewer's call; map it to gh's review event.
    pr="$(printf '%s'      "$record" | jq -r '.pr // empty'      2>/dev/null)"
    verdict="$(printf '%s' "$record" | jq -r '.verdict // empty' 2>/dev/null)"
    if _valid_rtype "$rtype" && [ -n "$body" ]; then
      if [ "$rtype" = "REVIEW" ] && [ -n "$pr" ]; then
        local event
        case "$verdict" in
          approve|approved)                                   event="approve" ;;
          request-changes|request_changes|changes-requested) event="request-changes" ;;
          comment) event="comment" ;;
          *) event="comment"
             [ -n "$verdict" ] && echo "dispatch: <- #${issue_number} '${persona}' unrecognized verdict '${verdict}' — posting as a plain PR comment" >&2 ;;
        esac
        if url="$("$here/review.sh" "$pr" --persona "$name" --tier "$role" --type "$rtype" --body "$body" --event "$event" --repo "$ghrepo" 2>&1)"; then
          outcome="dispatched"
          echo "dispatch: <- #${issue_number} '${persona}' posted ${rtype} on PR #${pr} (${event}) -> ${url}" >&2
          advance_state "$issue_number" "$rtype"   # #132: the REVIEW path must leave state:ready too
        else
          echo "dispatch: <- #${issue_number} '${persona}' PR-REVIEW POST FAILED (PR #${pr}):" >&2
          printf '%s\n' "$url" | sed 's/^/        /' >&2
          url=""
        fi
      elif url="$("$here/queue.sh" comment "$issue_number" --persona "$name" --tier "$role" --type "$rtype" --body "$body" --repo "$ghrepo" 2>&1)"; then
        outcome="dispatched"
        echo "dispatch: <- #${issue_number} '${persona}' posted ${rtype} -> ${url}" >&2
        advance_state "$issue_number" "$rtype"   # #132: drive the state machine forward off state:ready
      else
        echo "dispatch: <- #${issue_number} '${persona}' POST FAILED (${rtype}):" >&2
        printf '%s\n' "$url" | sed 's/^/        /' >&2
        url=""
      fi
    else
      echo "dispatch: <- #${issue_number} '${persona}' returned no valid record (rtype='${rtype}') — raw output:" >&2
      printf '%s\n' "$result" | sed 's/^/    | /' | head -40 >&2
    fi
  else
    echo "dispatch: <- #${issue_number} '${persona}' claude invocation FAILED" >&2
  fi

  local rl_extra=(); [ -n "$url" ] && rl_extra=(--artifact-url "$url")
  "$here/runlog.sh" append \
    --persona "$persona" \
    --repo    "$repo" \
    --trigger "dispatch" \
    --outcome "$outcome" \
    --record-type "dispatch" \
    --action  "dispatch" \
    --issue-number "$issue_number" \
    ${rl_extra[@]+"${rl_extra[@]}"} || true   # non-fatal: don't lose the dispatch over logging
}

# Readers first, concurrently, with NO writer lock. Each background job runs with its own
# stdout/stderr closed off the parent's inherited fds so it doesn't keep the cycle's caller
# pipe open past its work; the explicit `wait` below is the sole completion barrier.
reader_pids=()
for line in ${reader_lines[@]+"${reader_lines[@]}"}; do
  rn="${line%%$'\t'*}"; rp="${line#*$'\t'}"
  echo "dispatch: -> reader #${rn} '${rp}' (background)" >&2
  dispatch_one "$rn" "$rp" >/dev/null 2>&1 &
  reader_pids+=("$!")
done

# Writer second, foreground, serialized behind the writer lock (at most one per cycle).
locked=0
release_lock() { [ "$locked" -eq 1 ] && "$LOCK_SH" release --repo "$repo" >/dev/null 2>&1 || true; }
trap release_lock EXIT
if [ -n "$writer_line" ]; then
  wn="${writer_line%%$'\t'*}"; wp="${writer_line#*$'\t'}"
  "$LOCK_SH" claim --repo "$repo" --holder "$wp" >/dev/null
  locked=1
  dispatch_one "$wn" "$wp"
fi

# Wait for all background readers so the run-log is complete before the next cycle fires.
# This is the completion barrier: without it the parent would return while readers run
# orphaned and their run records would race the next scheduler trigger.
wait ${reader_pids[@]+"${reader_pids[@]}"}

exit 0

# ──────────────────────────────────────────────────────────────────────────────────────
# ENABLING THE SCHEDULE (left OFF by design):
#   This script runs exactly one cycle and stops. To run it on a cadence, point an
#   external scheduler at it — nothing is installed automatically. Examples:
#     cron:     */15 * * * * cd /path/to/persona-lab && scripts/dispatch.sh >> dispatch.log 2>&1
#     launchd:  a StartCalendarInterval/StartInterval job calling scripts/dispatch.sh
#   Keep PL_CLAUDE unset in production so the real `claude` binary is used; set it to a
#   stub in tests/dev so no paid-API call is made.
