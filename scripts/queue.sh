#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

cmd="${1:?usage: queue.sh <file|comment|label|close|query> ...}"; shift

# comment envelope (W1): float avatar + 2-row header, chip tier, plain body, small footer.
# tier may be "Tier · Role" — the Tier part renders as a chip, the Role as plain text.
pl_envelope() { # persona tier type body
  local persona="$1" tier="$2" rtype="$3" body="$4"
  local slug avatar tierchip role
  slug="$(printf '%s' "$persona" | tr '[:upper:]' '[:lower:]' | sed 's/é/e/g' | tr -d ' ')"
  avatar="https://raw.githubusercontent.com/ChristopherSchubert/persona-lab/main/assets/avatars/${slug}/${slug}-64.png"
  tierchip="${tier%% · *}"; role="${tier#* · }"; [ "$role" = "$tier" ] && role=""
  printf '<img src="%s" width="44" align="left">\n\n`AI` **%s** <kbd>%s</kbd>\n`%s`%s\n\n<br clear="all">\n\n%s\n\n<sub>%s</sub>\n' \
    "$avatar" "$persona" "$rtype" "$tierchip" "${role:+ · $role}" "$body" "$(date -u +%FT%TZ)"
}

case "$cmd" in
  file)
    persona="" tier="" rtype="FINDING" title="" body="" repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --title) title="$2"; shift 2;;
      --body) body="$2"; shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "unknown arg $1";; esac; done
    [ -n "$title" ] || pl_die "file requires --title"
    gh issue create ${repoflag[@]+"${repoflag[@]}"} --title "$title" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")"
    ;;
  comment)
    issue="${1:?comment <issue>}"; shift
    persona="" tier="" rtype="HANDOFF" body="" repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --body) body="$2"; shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "unknown arg $1";; esac; done
    gh issue comment ${repoflag[@]+"${repoflag[@]}"} "$issue" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")"
    ;;
  label)
    issue="${1:?label <issue>}"; shift; repoflag=(); addlabel=""; removelabel=""
    while [ $# -gt 0 ]; do case "$1" in
      --repo)   repoflag=(--repo "$2"); shift 2;;
      --add)    addlabel="$2"; shift 2;;
      --remove) removelabel="$2"; shift 2;;
      *) pl_die "label: unknown arg $1";; esac; done
    if [ -n "$addlabel" ]; then
      gh issue edit ${repoflag[@]+"${repoflag[@]}"} "$issue" --add-label "$addlabel"
    elif [ -n "$removelabel" ]; then
      gh issue edit ${repoflag[@]+"${repoflag[@]}"} "$issue" --remove-label "$removelabel"
    else
      pl_die "label needs --add/--remove"
    fi
    ;;
  close)
    issue="${1:?close <issue>}"; shift; reason="completed"; repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --reason) reason="$2"; shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "close: unknown arg $1";; esac; done
    gh issue close ${repoflag[@]+"${repoflag[@]}"} "$issue" --reason "$reason"
    ;;
  query)
    args=(issue list --json number,title,labels,state --limit 200)
    repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --label) args+=(--label "$2"); shift 2;;
      --state) args+=(--state "$2"); shift 2;;
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "query: unknown arg $1";;
    esac; done
    gh ${repoflag[@]+"${repoflag[@]}"} "${args[@]}"
    ;;

  park)
    # Write structured pl-fields block + label when an issue enters parked.
    # Required fields (ADR-0001 parked): blocker_type, owner, deadline, unblocking_ask.
    issue="${1:?park <issue>}"; shift
    blocker_type="" owner="" deadline="" unblocking_ask="" repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --blocker-type) blocker_type="$2"; shift 2;;
      --owner)        owner="$2"; shift 2;;
      --deadline)     deadline="$2"; shift 2;;
      --unblocking-ask) unblocking_ask="$2"; shift 2;;
      --repo)         repoflag=(--repo "$2"); shift 2;;
      *) pl_die "park: unknown arg $1";;
    esac; done
    # Guard: all required fields must be present
    [ -n "$blocker_type" ]   || pl_die "park: --blocker-type is required (ADR-0001 parked fields)"
    [ -n "$owner" ]          || pl_die "park: --owner is required (ADR-0001 parked fields)"
    [ -n "$deadline" ]       || pl_die "park: --deadline is required (ADR-0001 parked fields)"
    [ -n "$unblocking_ask" ] || pl_die "park: --unblocking-ask is required (ADR-0001 parked fields)"
    # Guard: blocker_type must be one of the ADR-0001 enum values
    case "$blocker_type" in
      dependency|coordination|clarification|decision|action) ;;
      *) pl_die "park: blocker_type '$blocker_type' is invalid; must be one of: dependency, coordination, clarification, decision, action";;
    esac
    # Structured write: embed pl-fields JSON as HTML comment in an IMPEDIMENT comment
    # Use jq -n --arg to safely encode values containing " or \
    pl_fields_json="$(jq -n \
      --arg blocker_type "$blocker_type" \
      --arg owner "$owner" \
      --arg deadline "$deadline" \
      --arg unblocking_ask "$unblocking_ask" \
      '{"blocker_type":$blocker_type,"owner":$owner,"deadline":$deadline,"unblocking_ask":$unblocking_ask}')"
    park_body="$(printf '<!-- pl-fields\n%s\n-->\n\nState → **parked**. Blocker: `%s`. Owner: %s. Deadline: %s.\n\nUnblocking ask: %s' \
      "$pl_fields_json" "$blocker_type" "$owner" "$deadline" "$unblocking_ask")"
    gh issue comment ${repoflag[@]+"${repoflag[@]}"} "$issue" --body "$park_body"
    gh issue edit   ${repoflag[@]+"${repoflag[@]}"} "$issue" --add-label "blocked-by:$blocker_type"
    ;;

  quarantine)
    # Write structured pl-fields block + label when an issue enters quarantine.
    # Required fields (ADR-0001 quarantine): owner, deadline, origin.
    issue="${1:?quarantine <issue>}"; shift
    owner="" deadline="" origin="" repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --owner)    owner="$2"; shift 2;;
      --deadline) deadline="$2"; shift 2;;
      --origin)   origin="$2"; shift 2;;
      --repo)     repoflag=(--repo "$2"); shift 2;;
      *) pl_die "quarantine: unknown arg $1";;
    esac; done
    # Guard: all required fields must be present
    [ -n "$owner" ]    || pl_die "quarantine: --owner is required (ADR-0001 quarantine fields)"
    [ -n "$deadline" ] || pl_die "quarantine: --deadline is required (ADR-0001 quarantine fields)"
    [ -n "$origin" ]   || pl_die "quarantine: --origin is required (ADR-0001 quarantine fields)"
    # Structured write: embed pl-fields JSON as HTML comment in a HANDOFF comment
    # Use jq -n --arg to safely encode values containing " or \
    pl_fields_json="$(jq -n \
      --arg owner "$owner" \
      --arg deadline "$deadline" \
      --arg origin "$origin" \
      '{"owner":$owner,"deadline":$deadline,"origin":$origin}')"
    q_body="$(printf '<!-- pl-fields\n%s\n-->\n\nState → **quarantine**. Owner: %s. Deadline: %s. Origin: `%s`.' \
      "$pl_fields_json" "$owner" "$deadline" "$origin")"
    gh issue comment ${repoflag[@]+"${repoflag[@]}"} "$issue" --body "$q_body"
    gh issue edit   ${repoflag[@]+"${repoflag[@]}"} "$issue" --add-label "quarantine"
    ;;

  resume)
    # Resume a parked issue: requires --resolution (blocker_resolution_cited per ADR-0001 RESUME guard).
    issue="${1:?resume <issue>}"; shift
    resolution="" repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --resolution) resolution="$2"; shift 2;;
      --repo)       repoflag=(--repo "$2"); shift 2;;
      *) pl_die "resume: unknown arg $1";;
    esac; done
    # Guard: resolution must be stated (ADR-0001 RESUME guard: blocker_resolution_cited)
    [ -n "$resolution" ] || pl_die "resume: --resolution is required (ADR-0001 RESUME guard: blocker_resolution_cited)"
    # Read blocker_type from the issue's pl-fields block (written into a comment by park).
    # Must use --json comments to fetch comment bodies; bare "gh issue view" returns only
    # the issue body which never contains the pl-fields block.
    fields_json="$(gh issue view ${repoflag[@]+"${repoflag[@]}"} "$issue" \
      --json comments --jq '[.comments[].body] | join("\n")' \
      | awk '/^<!-- pl-fields$/{found=1;next} found && /^-->$/{found=0;next} found{print;exit}')"
    [ -n "$fields_json" ] || pl_die "resume: no pl-fields block found in issue $issue (was it parked via queue.sh park?)"
    blocker_type="$(printf '%s' "$fields_json" | jq -r '.blocker_type')"
    [ -n "$blocker_type" ] && [ "$blocker_type" != "null" ] \
      || pl_die "resume: pl-fields block has no blocker_type field"
    resume_body="$(printf 'State → **ready** (resumed from parked).\n\nBlocker resolution: %s' "$resolution")"
    gh issue comment ${repoflag[@]+"${repoflag[@]}"} "$issue" --body "$resume_body"
    gh issue edit   ${repoflag[@]+"${repoflag[@]}"} "$issue" --remove-label "blocked-by:$blocker_type"
    ;;

  fields)
    # Read path: fetch issue body and extract the pl-fields JSON block.
    # Outputs the JSON object on stdout; exits 1 if no block found.
    issue="${1:?fields <issue>}"; shift
    repoflag=()
    while [ $# -gt 0 ]; do case "$1" in
      --repo) repoflag=(--repo "$2"); shift 2;;
      *) pl_die "fields: unknown arg $1";;
    esac; done
    # Fetch comment bodies; pl-fields block is written into comments by park/quarantine,
    # NOT into the issue body.  Must use --json comments to reach it.
    body="$(gh issue view ${repoflag[@]+"${repoflag[@]}"} "$issue" \
      --json comments --jq '[.comments[].body] | join("\n")')"
    # Extract the JSON from <!-- pl-fields\n{...}\n--> using awk (portable on macOS + Linux)
    extracted="$(printf '%s' "$body" | awk '/^<!-- pl-fields$/{found=1;next} found && /^-->$/{found=0;next} found{print;exit}')"
    if [ -z "$extracted" ]; then
      pl_die "fields: no pl-fields block found in issue $issue"
    fi
    printf '%s\n' "$extracted"
    ;;

  *) pl_die "unknown verb $cmd";;
esac
