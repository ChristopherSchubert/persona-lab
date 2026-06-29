#!/usr/bin/env bash
# Shared helpers. Source this; do not execute.
set -euo pipefail

# Colored-log palette for the reactors' stderr chatter (one shared definition, sourced by every
# script). Active ONLY when stderr is a real terminal and NO_COLOR is unset — so piped output, log
# files, and tests (which capture stderr, never a tty) stay plain. `[ -t 2 ]` sits in an `if` so
# set -e never trips on the non-tty case.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  PL_C_HEAD=$'\033[1;36m'; PL_C_OK=$'\033[1;32m'; PL_C_WARN=$'\033[1;33m'
  PL_C_ERR=$'\033[1;31m';  PL_C_DIM=$'\033[2m';   PL_C_RST=$'\033[0m'
else
  PL_C_HEAD=''; PL_C_OK=''; PL_C_WARN=''; PL_C_ERR=''; PL_C_DIM=''; PL_C_RST=''
fi

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

# Extract one JSON value (object or array) from a persona's result text. Single source of truth —
# scripts/dispatch.sh and scripts/audit-sweep.sh both delegate here (#153).
#
# Why this is strict about ordering: a persona's prose is frequently JSON-dense (a code review *of
# the parser* is saturated with JSON examples; findings quote `[roster]`/`[--grace-min N]`). The old
# greedy `(\[.*\]|\{.*\})` grabbed from the FIRST bracket — so an example, or a stray `[word]`, was
# returned instead of the real record, and good work was silently dropped (#153, Sarah's predicted
# edge case). The strengthened contract: the dispatch/sweep prompts require the record as the FINAL
# ```-fenced block, and extraction honors that — preferring the LAST fence, then (degraded) the LAST
# top-level value. An *example that precedes the record* can therefore never win.
#
# Order of attempts (first that yields valid JSON wins; prints compact JSON, returns 0):
#   1. The whole input is already clean JSON.
#   2. The content of the LAST ```-fenced block (per-block, last→first) — the canonical path.
#   3. Degraded fallback for unfenced output: a string/escape-aware balanced-bracket scan returning
#      top-level candidates LAST→first, so the final value (the real record) wins over earlier ones.
pl_extract_json() {
  local in cand; in="$(cat)"
  # 1) Already clean JSON.
  printf '%s' "$in" | jq -ce . 2>/dev/null && return 0
  # 2) Each ```-fenced block's content, LAST block first (the prompt requires the record last).
  while IFS= read -r -d '' cand; do
    [ -n "$cand" ] || continue
    printf '%s' "$cand" | jq -ce . 2>/dev/null && return 0
  done < <(printf '%s' "$in" | _pl_fenced_blocks)
  # 3) Degraded: balanced top-level JSON candidates, LAST first.
  while IFS= read -r -d '' cand; do
    printf '%s' "$cand" | jq -ce . 2>/dev/null && return 0
  done < <(printf '%s' "$in" | _pl_json_candidates)
  return 1
}

# Emit the content of each ```-fenced block, NUL-separated, in REVERSE order (last block first).
# A fence delimiter is a line whose first non-space chars are ``` (optionally with a language tag).
_pl_fenced_blocks() {
  perl -0777 -ne '
    my @blocks; my ($in,$cur)=(0,"");
    for my $line (split /\n/, $_, -1) {
      if ($line =~ /^\s*```/) {
        if ($in) { push @blocks, $cur; ($in,$cur)=(0,""); } else { ($in,$cur)=(1,""); }
        next;
      }
      $cur .= $line . "\n" if $in;
    }
    print $_, "\0" for reverse @blocks;
  '
}

# Emit each top-level balanced {…}/[…] candidate, NUL-separated, in REVERSE order (last first).
# String/escape aware so brackets inside JSON strings do not corrupt the depth count.
_pl_json_candidates() {
  perl -0777 -ne '
    my $s=$_; my $len=length $s; my $i=0; my @c;
    while ($i < $len) {
      my $ch = substr($s,$i,1);
      if ($ch eq "{" || $ch eq "[") {
        my ($d,$j,$instr,$esc) = (0,$i,0,0);
        while ($j < $len) {
          my $x = substr($s,$j,1);
          if ($instr)            { if ($esc){$esc=0} elsif ($x eq "\\"){$esc=1} elsif ($x eq "\""){$instr=0} }
          elsif ($x eq "\"")     { $instr=1 }
          elsif ($x eq "{" || $x eq "[") { $d++ }
          elsif ($x eq "}" || $x eq "]") { $d--; last if $d==0 }
          $j++;
        }
        if ($d==0 && $j < $len) { push @c, substr($s,$i,$j-$i+1); $i=$j+1; next; }
      }
      $i++;
    }
    print $_, "\0" for reverse @c;
  '
}

pl_die() { echo "persona-lab: $*" >&2; exit 1; }
