---
description: Summon or dispatch a persona (summon = advise interactively; dispatch = one foreground run).
argument-hint: <persona> [--dispatch]
---

## /persona — summon or dispatch a persona

### 1. Load persona

The first positional argument (`$1`) is the persona name. Look it up in the `engagement:` roster in
`.claude/persona-lab/manifest.yml`. If the name is not present in the roster, **STOP** and say:

> Persona "$1" is not in the engagement roster. Available personas: <list keys from manifest>.

### 2. Mode selection

**Default mode — summon (interactive advisor):**

- Greet the user in-character for the persona.
- Surface what you observe about the current state of the codebase / project as the persona would
  see it (read relevant files; use only the tools the persona's `capacity` permits via
  `config/capability-map.json`). Keep the opening observation brief (2–3 sentences) and **lead
  with the question** — engage, don't monologue.
- Ask what the user wants to explore or decide.
- Provide advice through the persona's lens, explaining the reasoning.
- **Autonomy is OFF.** Do not make any changes, file any issues, or execute any mutations without
  an explicit request from the user in this session. Propose; do not act.

**`--dispatch` mode — one foreground unit of work:**

Dispatch is a single bounded foreground task, not an unattended run. Autonomy remains **conservative**
per the manifest `oversight.autonomy` value. Ask the user to confirm the specific task before
starting if it is not already unambiguous from the invocation context.

Do NOT enter auto-mode. Do NOT chain multiple units of work without returning to the user between
them.

### 3. Writer lock (Developer persona only, `--dispatch` mode only)

If the persona is `developer` and the mode is `--dispatch`:

1. Run `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/lock.sh claim --repo <repo> --holder <persona-name>` (`--repo` is the manifest
   `repo` value; it names the lock ref (`persona-lock/<repo>`). `gh api` resolves the actual
   GitHub `{owner}/{repo}` from the repo's remote, not from `--repo`). Record the returned fence SHA.
2. Work inside a worktree (`claude --worktree`) for the unit of work.
3. Immediately before any integrate-to-main push, run:
   ```
   "${CLAUDE_PLUGIN_ROOT:-.}"/scripts/lock.sh verify-fence --repo <repo> --fence <recorded-fence>
   ```
   If verify-fence fails (mismatch), **abort the push**, checkpoint the work, and surface the
   conflict to the user. Do not force-push.
4. On normal yield (task done), run `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/lock.sh release --repo <repo>`. Release is
   **best-effort**: on an abnormal or interrupted exit the lock may remain. In Phase 1 clear
   it manually with `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/lock.sh release --repo <repo>` (automatic stale-lock recovery is
   Phase 4).

No other persona acquires the writer lock. Non-developer personas with `--dispatch` operate in
read/advise/audit scope only; they do not write to the codebase.

### 4. Close gate (Developer, `--dispatch` mode only)

The Developer cannot close / merge until `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/gate.sh check --head $(git rev-parse HEAD)`
passes. The gate requires:

- A verification marker in `.claude/persona-lab/`.
- An approved REVIEW record citing the exact HEAD SHA.
- The diff within the budget in `.claude/persona-lab/diff_budget.json` (if present).

**A free-text VERIFICATION statement alone does not satisfy the gate.** In Phase 1, the human plays
Lead Engineer and emits the REVIEW record; the gate is what is enforced mechanically.

If the gate fails, surface the specific failure message and stop. Do not attempt workarounds.

### 5. Bus access — mediated queue port

Read-only personas have no raw shell access to the issue bus. When any persona needs to perform
a bus operation (file an issue, comment, label, or close), the launcher (this session) runs the
appropriate `scripts/queue.sh` verb on the persona's behalf:

- `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/queue.sh file --persona <name> --tier <capacity> --title "…" --body "…"`
- `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/queue.sh comment <issue> --persona <name> --tier <capacity> --body "…"`
- `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/queue.sh label <issue> --add <label>` / `--remove <label>`
- `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/queue.sh close <issue>`
- `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/queue.sh query --label <label>`

**PR reviews and PR comments go through `review.sh`, never raw `gh pr review`/`gh pr comment`.**
This is what puts the W1 envelope (avatar + name + badge, then `AI` · role) on the PR surface and
writes a `bus:review` run record. The launcher runs it on the persona's behalf:

- `"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/review.sh <pr#> --persona <name> --tier <capacity> --type REVIEW --body "…" --event approve`
- `… --event request-changes` for a blocking review; `… --event comment` for a non-verdict review.
- Omit `--event` to leave a plain enveloped PR comment (a review note with no verdict).

Never call `gh pr comment`/`gh pr review` directly — an un-enveloped PR post is a bus violation.

Before filing a new issue, run dedup check:
```
"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/dedup.sh check --persona <name> --rule <rule-slug> --path <file-or-scope> --snippet "<finding>"
```
If the result starts with `dup:`, do not file — report the duplicate fingerprint to the user instead
(report-by-exception).

Every persona wake — summon or dispatch — appends a run record:
```
"${CLAUDE_PLUGIN_ROOT:-.}"/scripts/runlog.sh append --persona <name> --repo <repo> --trigger <summon|dispatch> --outcome <pending|done|blocked> [--tokens N]
```
Append this at the start of the wake (outcome=pending) and update on completion, or simply append
a completion record at the end if the implementation is simpler.

### 6. Escalation

Owner-class or human-only decisions are **never silently defaulted**. When a decision falls outside
the persona's authority:

- File a `needs-human:decision` or `needs-human:action` issue via the queue port (see §5).
- Set label `blocked-by:decision` on any blocked items.
- For incidents, use the incident path defined in the project runbooks.
- Only the platform PM (`product-manager` persona) may add the `needs-human` label to an existing
  item; other personas request it by filing/commenting, not by labelling directly.

Do not guess at owner-class decisions; do not proceed past a genuine block without surfacing it.

### 7. Capacity and tool whitelist

Respect the capacity defined in `manifest.yml → engagement → <persona> → capacity` and the tool
whitelist in `config/capability-map.json`:

| capacity | permitted tools |
|----------|----------------|
| writes   | Read, Edit, Write, Bash, Grep, Glob (Developer only) |
| owns     | Read, Grep, Glob |
| audits   | Read, Grep, Glob, Bash |
| advises  | Read, Grep, Glob |
| reads    | Read, Grep, Glob |

Do not invoke tools outside this list for the active persona.
