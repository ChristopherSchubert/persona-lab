#!/usr/bin/env bash
# Shared helpers. Source this; do not execute.
set -euo pipefail

pl_repo_root() { git rev-parse --show-toplevel; }

pl_config_dir() { echo "${PL_CONFIG_DIR:-$(pl_repo_root)/.claude/persona-lab}"; }

# Read a scalar from the manifest (yq if present, else a grep fallback for top-level only).
pl_manifest_get() {
  local key="$1" mf; mf="$(pl_config_dir)/manifest.yml"
  if command -v yq >/dev/null 2>&1; then
    yq -r ".${key} // \"\"" "$mf"
  else
    # Fallback handles top-level scalars only; nested (dotted) keys require yq — fail closed.
    if [[ "$key" == *.* ]]; then
      pl_die "pl_manifest_get: nested key '$key' requires yq (brew install yq)"
    fi
    grep -E "^${key}:[[:space:]]" "$mf" | head -1 | sed -E "s/^${key}:[[:space:]]*///"
  fi
}

# Resolve a gh-valid "OWNER/REPO" for the active repo. The manifest `repo` may be a short logical
# name (it scopes the lock ref, where any string is fine), but `gh --repo` requires OWNER/REPO —
# so if it isn't already OWNER/REPO, fall back to the cwd repo's nameWithOwner. Used by the
# dispatch/audit harness when posting to the bus so `gh --repo <short>` never fails.
pl_gh_repo() {
  local r nwo
  r="${PL_REPO:-$(pl_manifest_get repo 2>/dev/null || echo "")}"
  case "$r" in */*) printf '%s' "$r"; return;; esac
  nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -n "$nwo" ] && printf '%s' "$nwo" || printf '%s' "$r"
}

# Fetch an issue's full context (title, labels, body, comments) as a markdown block, so the harness
# can hand a dispatched persona the task it cannot read itself (most personas have no gh/Bash; #125).
# Args: <issue-number> <owner/repo>. Prints empty on any failure (caller degrades gracefully).
pl_issue_context() {
  local num="$1" repo="$2"
  gh issue view "$num" --repo "$repo" --json number,title,body,labels,comments --jq '
    "## Your task — issue #\(.number): \(.title)\n\n**Labels:** " + ([.labels[].name] | join(", ")) +
    "\n\n" + (.body // "(no body)") +
    "\n\n## Records/comments on this issue so far:\n\n" +
    ( [.comments[].body] | if length == 0 then "(none yet)" else join("\n\n———\n\n") end )
  ' 2>/dev/null || true
}

# Resolve the directory where run records are written/read.
# Precedence: PL_RUNS_DIR (test-isolation override) > PL_RUNS (legacy override) > config default.
# Tests set PL_RUNS_DIR to a temp dir so they never pollute the real runs dir.
pl_runs_dir() { echo "${PL_RUNS_DIR:-${PL_RUNS:-$(pl_config_dir)/runs}}"; }

# W1 comment envelope: single-line float (img + name + badge), then `AI` · role, then body.
# Shared by queue.sh (issue comments/files) and review.sh (PR reviews/comments) so the
# bus and PR surfaces render identically. tier may be "Tier · Role" — only the Role shows.
pl_envelope() { # persona tier type body
  local persona="$1" tier="$2" rtype="$3" body="$4"
  local slug avatar role color
  slug="$(printf '%s' "$persona" | tr '[:upper:]' '[:lower:]' | sed 's/é/e/g' | tr -d ' ')"
  avatar="https://raw.githubusercontent.com/ChristopherSchubert/persona-lab/main/assets/avatars/${slug}/${slug}-64.png"
  role="${tier#* · }"; [ "$role" = "$tier" ] && role="$tier"
  case "$rtype" in
    PROPOSAL|ROUTING)             color=8b5cf6 ;;
    DECISION)                     color=2563eb ;;
    DELIVERED)                    color=16a34a ;;
    ASSESSMENT)                   color=f59e0b ;;
    HANDOFF)                      color=0891b2 ;;
    REVIEW)                       color=06b6d4 ;;
    BLOCKER|PUSHBACK)             color=dc2626 ;;
    FEEDBACK)                     color=14b8a6 ;;
    ASK)                          color=d946ef ;;
    REPLY)                        color=a855f7 ;;
    *)                            color=64748b ;;
  esac
  # Approved envelope: single-line float (img + name + badge), then `AI` · role. No <br clear>, no footer.
  printf '<img src="%s" width="44" align="left"> **%s** <img src="https://img.shields.io/badge/%s-%s?style=flat-square" height="16" align="texttop">\n`AI` · %s\n\n%s\n' \
    "$avatar" "$persona" "$rtype" "$color" "$role" "$body"
}

# Best-effort extract one JSON value (object OR array) from a persona's result text. The model
# may return clean JSON, a ```-fenced block, or JSON wrapped in prose. Reads stdin; on success
# prints the compact JSON and returns 0; returns 1 if nothing parses.
#
# Order matters (issue #153 — Sarah's predicted "[note] … {json}" edge case):
#   1. already-clean JSON — pass straight through.
#   2. content INSIDE a ``` fence — print ONLY fenced lines (the model fences its JSON), so prose
#      OUTSIDE the fence that itself contains "[" / "{" (e.g. a finding *about* "[roster]" copy, or
#      a "[--grace-min N]" flag) can't corrupt the parse.
#   3. balanced-bracket scan — emit each top-level [...]/{...} candidate (string/escape aware) and
#      return the FIRST that validates as JSON. This replaces a greedy `(\[.*\]|\{.*\})` first-[ match
#      that grabbed from a prose bracket through the array's last "]", yielding invalid JSON and
#      silently dropping real findings/records.
# Known limit: if prose contains a *coincidentally valid* JSON value (e.g. "[1, 2]") before the real
# one and neither is fenced, step 3 returns the prose value. Fencing (step 2) avoids this; personas fence.
pl_extract_json() {
  local in cand; in="$(cat)"
  printf '%s' "$in" | jq -ce . 2>/dev/null && return 0
  printf '%s' "$in" | awk '/^[[:space:]]*```/{f=!f; next} f' | jq -ce . 2>/dev/null && return 0
  while IFS= read -r -d '' cand; do
    printf '%s' "$cand" | jq -ce . 2>/dev/null && return 0
  done < <(printf '%s' "$in" | perl -0777 -ne '
    my $s=$_; my $len=length $s; my $i=0;
    while ($i<$len) {
      my $c=substr($s,$i,1);
      if ($c eq "{" || $c eq "[") {
        my ($d,$j,$instr,$esc)=(0,$i,0,0);
        while ($j<$len) {
          my $x=substr($s,$j,1);
          if ($instr) { if ($esc){$esc=0} elsif ($x eq "\\"){$esc=1} elsif ($x eq "\""){$instr=0} }
          elsif ($x eq "\""){$instr=1}
          elsif ($x eq "{" || $x eq "["){$d++}
          elsif ($x eq "}" || $x eq "]"){$d--; if($d==0){last}}
          $j++;
        }
        if ($d==0 && $j<$len){ print substr($s,$i,$j-$i+1), "\0"; $i=$j+1; next; }
      }
      $i++;
    }')
  return 1
}

pl_die() { echo "persona-lab: $*" >&2; exit 1; }
