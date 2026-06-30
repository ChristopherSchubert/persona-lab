#!/usr/bin/env bash
# cycle.sh — the CONDUCTOR: one full SDLC pass over the bus, so you run ONE command, not six.
# It chains the reactors in dependency order:
#
#   triage-reviews  → PM routes open PRs into review tasks   (produce→review trigger)
#   dispatch        → work one mutator + N readers           (dev work + reviews → verdicts auto-label)
#   integrate       → merge PRs whose gates are green         (checkpointed)
#   accept          → PM acceptance-close of merged work      (proof-first)
#
# Each stage is best-effort: a transient failure in one is logged but does NOT abort the pass, so a
# single pass always advances every other stage. Run it from a terminal or a scheduler (e.g. every few
# hours). Each stage is a real reactor invoked via ${PL_*_SH:-$here/<stage>.sh}, overridable for tests.
#
# --drain (loop to quiescence — the once-a-day backlog cleaner, #187) is intentionally REFUSED until
# worktree isolation (#109) is on main: looping dispatch without it re-entangles branches. Single-pass
# is safe today (one mutator per pass, same as a bare dispatch).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

passthru=()
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) passthru+=(--dry-run); shift;;
  --repo)    export PL_REPO="$2"; shift 2;;   # via env — every reactor honors PL_REPO (dispatch has no --repo flag)
  --drain)   pl_die "cycle: --drain (loop-to-quiescence, #187) is not enabled yet — it requires worktree isolation (#109) on main, else looping dispatch re-entangles branches. Run cycle.sh (single pass) repeatedly for now.";;
  *)         pl_die "cycle: unknown arg $1";;
esac; done

# OPTIONAL bot identity (#218 — always optional, never enforced). If a bot.env exists, source it so
# the bus acts as a scoped bot (GH_TOKEN) instead of your own gh login. Default path is OUTSIDE the
# repo (no commit risk); override with PL_BOT_ENV. ABSENT IS THE NORMAL PATH — you run as yourself,
# no error. This never decides identity for you; it only loads what you opted into.
bot_env="${PL_BOT_ENV:-$HOME/.config/persona-lab/bot.env}"
if [ -f "$bot_env" ]; then
  . "$bot_env"
  # Make the bot identity fully EPHEMERAL — scoped to THIS process tree, never your shell or global
  # git config (no `gh auth setup-git` required). gh already honors GH_TOKEN; for git push over HTTPS
  # we inject a per-process credential helper + author identity via GIT_CONFIG_* (git 2.31+). When
  # the script exits, your CLI is untouched.
  if [ -n "${GH_TOKEN:-}" ]; then
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0="credential.https://github.com.helper" GIT_CONFIG_VALUE_0=""   # reset inherited helpers
    export GIT_CONFIG_KEY_1="credential.https://github.com.helper" \
           GIT_CONFIG_VALUE_1='!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$GH_TOKEN"; }; f'
    export GIT_AUTHOR_NAME="${PL_BOT_NAME:-persona-lab-gh}"     GIT_COMMITTER_NAME="${PL_BOT_NAME:-persona-lab-gh}"
    export GIT_AUTHOR_EMAIL="${PL_BOT_EMAIL:-persona-lab-gh@users.noreply.github.com}" \
           GIT_COMMITTER_EMAIL="${PL_BOT_EMAIL:-persona-lab-gh@users.noreply.github.com}"
  fi
  echo "${PL_C_HEAD}cycle: bot identity loaded from ${bot_env} (ephemeral — your shell/global git config untouched)${PL_C_RST}" >&2
else
  echo "${PL_C_DIM}cycle: no bot.env — running as your own gh identity (set PL_BOT_ENV to opt into a bot)${PL_C_RST}" >&2
fi

TRIAGE_SH="${PL_TRIAGE_SH:-$here/triage-reviews.sh}"
DISPATCH_SH="${PL_DISPATCH_SH:-$here/dispatch.sh}"
INTEGRATE_SH="${PL_INTEGRATE_SH:-$here/integrate.sh}"
ACCEPT_SH="${PL_ACCEPT_SH:-$here/accept.sh}"

# Run one stage best-effort: log it, never let its failure abort the whole pass.
stage() {
  local label="$1" sh="$2"; shift 2
  echo "${PL_C_HEAD}cycle: ── ${label} ───────────────────────────────${PL_C_RST}" >&2
  if ! "$sh" "$@"; then
    echo "${PL_C_WARN}cycle: ${label} exited non-zero — continuing the pass (next stage)${PL_C_RST}" >&2
  fi
}

echo "${PL_C_HEAD}cycle: one full SDLC pass (triage-reviews → dispatch → integrate → accept)${PL_C_RST}" >&2
stage "triage-reviews" "$TRIAGE_SH"    ${passthru[@]+"${passthru[@]}"}
stage "dispatch"       "$DISPATCH_SH"  ${passthru[@]+"${passthru[@]}"}
stage "integrate"      "$INTEGRATE_SH" ${passthru[@]+"${passthru[@]}"}
stage "accept"         "$ACCEPT_SH"    ${passthru[@]+"${passthru[@]}"}
echo "${PL_C_OK}cycle: pass complete${PL_C_RST}" >&2
exit 0
