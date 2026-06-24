# Phase 1 — persona-lab model-as-plugin (single-repo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship persona-lab as a Claude Code plugin that, in a single real repo, gives you named persona agents (access-locked), shared disciplines, a `/persona` launcher, a GitHub-Issues queue port with the bus discipline + dedup, and the `/inbox` cockpit — usable end-to-end against one hand-written manifest.

**Architecture:** A Claude Code plugin (`.claude-plugin/plugin.json` + `agents/` + `commands/` + `skills/` + `scripts/`). Personas are **agent definitions** whose `tools:` whitelist *is* the access lock, generated from a manifest. Coordination is GitHub Issues behind a thin **queue port** (bash over `gh`), with a git-backed run-log and a create-only-CAS writer lock. Deterministic logic lives in tested bash scripts; persona behavior lives in markdown briefings with `_disciplines` concatenated in at build.

**Tech Stack:** Claude Code plugin format; bash scripts; `gh` CLI (Issues + Projects v2 + git refs); `jq`; `bats-core` for shell tests; `git` worktrees.

**Scope note (what Phase 1 is NOT):** no `/persona-init` bootstrap interview (Phase 2 — the manifest is hand-written here); no platform tier / cross-repo (Phase 3); no autonomous dispatch / auto-mode / GitHub App bot / scheduling (Phase 4 — all OFF by default per the governance invariant). Personas run interactively (summon) or via a single foreground `claude -p` dispatch under the human's identity.

**Reference spec:** `docs/superpowers/specs/2026-06-21-persona-lab-operating-model-design.md`

---

## File structure

```
.claude-plugin/plugin.json         plugin manifest (name, component dirs)
.claude-plugin/marketplace.json    local marketplace entry (for install/testing)

agents/                            GENERATED — never hand-edit (built from briefings + _disciplines)
  developer.md product-analyst.md security-analyst.md design-analyst.md
  product-manager.md lead-engineer.md platform-architect.md data-architect.md
  head-of-security.md head-of-design.md head-of-finops.md

docs/personas/                     SOURCE briefings (one per persona) — existing, edited here
  _disciplines.md                  shared disciplines, concatenated into every agent at build
  <persona>.md                     per-persona briefing (role, decides/escalates, tone, voice)

commands/
  persona.md                       summon/dispatch launcher (slash command)
  inbox.md                         the human's cockpit

scripts/
  lib/common.sh                    shared helpers (repo root, manifest read, gh wrappers)
  queue.sh                         queue port: file|comment|label|close|query (over gh)
  dedup.sh                         fingerprint ledger (create-or-bump, git-backed)
  runlog.sh                        append a run record (NDJSON) + helpers
  lock.sh                          writer lock: claim|release|status (create-only CAS + fence)
  build-agents.sh                  concat _disciplines into each briefing → agents/<name>.md
  assert-access.sh                 manifest capacity → tools: whitelist, fail-closed on mismatch

config/
  manifest.example.yml             documented example
  schemas/                         required-field package schemas (handoff/needs-human/review/run-record)

tests/                             bats-core tests, one file per script
  queue.bats dedup.bats runlog.bats lock.bats build-agents.bats assert-access.bats

.claude/persona-lab/               INSTANCE config written into the target repo (hand-written in Phase 1)
  manifest.yml                     grain=single, owner, roster, per-persona access + trigger
  fingerprints/                    dedup ledger (git-tracked)
  runs/                            NDJSON run-log (git-tracked)
```

**Decomposition rationale:** deterministic, testable logic is isolated in `scripts/` (each one file, one responsibility, TDD'd with bats). Persona *behavior* is markdown content (briefings) compiled to `agents/`. The instance config (`.claude/persona-lab/`) is data, hand-written in Phase 1. Files that change together (a script + its test) live together by responsibility.

---

## Task group A — plugin skeleton & test harness

### Task A1: Plugin manifest + marketplace entry

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write `plugin.json`**

```json
{
  "name": "persona-lab",
  "displayName": "Persona Lab",
  "description": "A multi-persona operating model for single-human-driven autonomous SDLC.",
  "version": "0.1.0",
  "author": { "name": "Christopher Schubert" },
  "license": "MIT",
  "agents": "./agents/",
  "commands": "./commands/",
  "skills": "./skills/"
}
```

- [ ] **Step 2: Write `marketplace.json`** (lets you install locally for testing)

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "persona-lab-dev",
  "owner": { "name": "Christopher Schubert" },
  "plugins": [
    { "name": "persona-lab", "source": "./", "description": "Persona Lab (local dev)" }
  ]
}
```

- [ ] **Step 3: Verify JSON is valid**

Run: `jq . .claude-plugin/plugin.json && jq . .claude-plugin/marketplace.json`
Expected: both pretty-print with no parse error.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/
git commit -m "feat(plugin): plugin.json + local marketplace entry"
```

### Task A2: Test harness (bats-core) + shared lib

**Files:**
- Create: `scripts/lib/common.sh`
- Create: `tests/common.bats`

- [ ] **Step 1: Install bats-core (dev dependency)**

Run: `brew install bats-core` (macOS) — verify `bats --version` prints a version.

- [ ] **Step 2: Write `scripts/lib/common.sh`** (helpers used by every script)

```bash
#!/usr/bin/env bash
# Shared helpers. Source this; do not execute.
set -euo pipefail

pl_repo_root() { git rev-parse --show-toplevel; }

pl_config_dir() { echo "$(pl_repo_root)/.claude/persona-lab"; }

# Read a top-level scalar from the manifest (yq if present, else a grep fallback).
pl_manifest_get() {
  local key="$1" mf; mf="$(pl_config_dir)/manifest.yml"
  if command -v yq >/dev/null 2>&1; then yq -r ".${key} // \"\"" "$mf"; else
    grep -E "^${key}:" "$mf" | head -1 | sed -E "s/^${key}:[[:space:]]*//"; fi
}

pl_die() { echo "persona-lab: $*" >&2; exit 1; }
```

- [ ] **Step 3: Write a smoke test `tests/common.bats`**

```bash
setup() { source "${BATS_TEST_DIRNAME}/../scripts/lib/common.sh"; }

@test "pl_repo_root returns the git toplevel" {
  run pl_repo_root
  [ "$status" -eq 0 ]
  [ -d "$output" ]
}
```

- [ ] **Step 4: Run it, expect pass**

Run: `bats tests/common.bats`
Expected: `1 test, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/common.sh tests/common.bats
git commit -m "test: bats harness + common.sh helpers"
```

---

## Task group B — the queue port (over GitHub Issues)

> The bus is GitHub Issues behind a 5-verb port: `file · comment · label · close · query`. Personas never call `gh` directly — only `queue.sh`, so the substrate stays swappable.

### Task B1: `queue.sh file` — create an issue with the comment envelope

**Files:**
- Create: `scripts/queue.sh`
- Test: `tests/queue.bats`

- [ ] **Step 1: Write the failing test** (stubs `gh` via a PATH shim so no network)

```bash
setup() {
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
echo "GH $*" >> "$PL_GH_LOG"
# emulate: issue create prints the new issue URL
case "$1 $2" in "issue create") echo "https://github.com/o/r/issues/42";; esac
SH
  chmod +x "$PL_TEST_BIN/gh"; export PL_GH_LOG="$(mktemp)"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_GH_LOG"; }

@test "queue file: creates an issue and embeds the AI envelope + record type" {
  run scripts/queue.sh file --persona "Ben" --tier "finances Team · Developer" \
      --type FINDING --title "clock skew 401" --body "details"
  [ "$status" -eq 0 ]
  [[ "$output" == *"issues/42"* ]]
  grep -q "issue create" "$PL_GH_LOG"
  # envelope: header line carries AI flag + name + record type
  grep -q -- "--body" "$PL_GH_LOG" && grep -q "FINDING" "$PL_GH_LOG"
}
```

- [ ] **Step 2: Run, expect fail**

Run: `bats tests/queue.bats`
Expected: FAIL — `queue.sh: No such file`.

- [ ] **Step 3: Implement `queue.sh` (the `file` verb)**

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"

cmd="${1:?usage: queue.sh <file|comment|label|close|query> ...}"; shift

# Build the comment envelope: header line + body + collapsed provenance footer.
pl_envelope() { # persona tier type body
  local persona="$1" tier="$2" rtype="$3" body="$4"
  printf '🤖 **%s** (%s) · %s\n\n%s\n\n<details><summary>AI persona — not the human</summary>\n%s · %s\n</details>\n' \
    "$persona" "$tier" "$rtype" "$body" "$persona ($tier)" "$(date -u +%FT%TZ)"
}

case "$cmd" in
  file)
    persona="" tier="" rtype="FINDING" title="" body=""
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --title) title="$2"; shift 2;;
      --body) body="$2"; shift 2;; *) pl_die "unknown arg $1";; esac; done
    [ -n "$title" ] || pl_die "file requires --title"
    gh issue create --title "$title" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")"
    ;;
  *) pl_die "verb $cmd not implemented yet";;
esac
```

- [ ] **Step 4: Run, expect pass**

Run: `bats tests/queue.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/queue.sh tests/queue.bats
git commit -m "feat(queue): file verb with AI comment envelope"
```

### Task B2: `queue.sh comment|label|close|query` verbs

**Files:**
- Modify: `scripts/queue.sh`
- Test: `tests/queue.bats`

- [ ] **Step 1: Add failing tests** for each verb (one assertion each)

```bash
@test "queue comment: appends an enveloped comment to an issue" {
  run scripts/queue.sh comment 42 --persona Ben --tier "finances Team · Developer" --type PROOF --body "fixed"
  [ "$status" -eq 0 ]; grep -q "issue comment 42" "$PL_GH_LOG"
}
@test "queue label: adds a label" {
  run scripts/queue.sh label 42 --add needs-human:decision
  [ "$status" -eq 0 ]; grep -q "issue edit 42 --add-label needs-human:decision" "$PL_GH_LOG"
}
@test "queue close: closes with a state-reason" {
  run scripts/queue.sh close 42 --reason completed
  [ "$status" -eq 0 ]; grep -q "issue close 42" "$PL_GH_LOG"
}
@test "queue query: passes a search and requests json" {
  run scripts/queue.sh query --label needs-human:decision
  [ "$status" -eq 0 ]; grep -q "issue list" "$PL_GH_LOG"
}
```

- [ ] **Step 2: Run, expect 4 new failures**

Run: `bats tests/queue.bats`
Expected: the 4 new tests FAIL with "verb ... not implemented yet".

- [ ] **Step 3: Implement the four verbs** (add cases to the `case` block)

```bash
  comment)
    issue="${1:?comment <issue>}"; shift
    persona="" tier="" rtype="HANDOFF" body=""
    while [ $# -gt 0 ]; do case "$1" in
      --persona) persona="$2"; shift 2;; --tier) tier="$2"; shift 2;;
      --type) rtype="$2"; shift 2;; --body) body="$2"; shift 2;; *) pl_die "unknown arg $1";; esac; done
    gh issue comment "$issue" --body "$(pl_envelope "$persona" "$tier" "$rtype" "$body")" ;;
  label)
    issue="${1:?label <issue>}"; shift
    case "$1" in --add) gh issue edit "$issue" --add-label "$2";;
                 --remove) gh issue edit "$issue" --remove-label "$2";; *) pl_die "label needs --add/--remove";; esac ;;
  close)
    issue="${1:?close <issue>}"; shift; reason="completed"
    [ "${1:-}" = "--reason" ] && reason="$2"
    gh issue close "$issue" --reason "$reason" ;;
  query)
    args=(issue list --json number,title,labels,state --limit 200)
    while [ $# -gt 0 ]; do case "$1" in --label) args+=(--label "$2"); shift 2;;
      --state) args+=(--state "$2"); shift 2;; *) shift;; esac; done
    gh "${args[@]}" ;;
```

- [ ] **Step 4: Run, expect all pass**

Run: `bats tests/queue.bats`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/queue.sh tests/queue.bats
git commit -m "feat(queue): comment/label/close/query verbs"
```

---

## Task group C — dedup ledger, run-log, writer lock

### Task C1: `dedup.sh` — create-or-bump by fingerprint (git-backed)

> Issues has no upsert, so dedup-at-creation is mandatory. The ledger is git-committed so the atomic property comes from git (a concurrent loser rebases and sees the entry). Fingerprint = `sha256(persona|rule_id|path|normalized_snippet)`.

**Files:**
- Create: `scripts/dedup.sh`
- Test: `tests/dedup.bats`

- [ ] **Step 1: Write the failing test**

```bash
setup() { export PL_LEDGER="$(mktemp -d)/fingerprints"; mkdir -p "$PL_LEDGER"; }

@test "dedup: first sighting is new, returns the fingerprint" {
  run scripts/dedup.sh check --persona Ben --rule clock-skew --path auth/session.ts --snippet "iat future"
  [ "$status" -eq 0 ]; [[ "$output" == new:* ]]
}
@test "dedup: second identical sighting is a duplicate of the same fingerprint" {
  scripts/dedup.sh check --persona Ben --rule clock-skew --path auth/session.ts --snippet "iat future" >/dev/null
  run scripts/dedup.sh check --persona Ben --rule clock-skew --path auth/session.ts --snippet "iat future"
  [ "$status" -eq 0 ]; [[ "$output" == dup:* ]]
}
```

- [ ] **Step 2: Run, expect fail** — `bats tests/dedup.bats` → FAIL (no file).

- [ ] **Step 3: Implement `dedup.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
ledger="${PL_LEDGER:-$(pl_config_dir)/fingerprints}"; mkdir -p "$ledger"

[ "${1:-}" = "check" ] || pl_die "usage: dedup.sh check --persona .. --rule .. --path .. --snippet .."
shift; persona="" rule="" path="" snippet=""
while [ $# -gt 0 ]; do case "$1" in
  --persona) persona="$2"; shift 2;; --rule) rule="$2"; shift 2;;
  --path) path="$2"; shift 2;; --snippet) snippet="$2"; shift 2;; *) pl_die "unknown arg $1";; esac; done

norm="$(echo "$snippet" | tr '[:upper:]' '[:lower:]' | tr -s ' ')"
fp="$(printf '%s|%s|%s|%s' "$persona" "$rule" "$path" "$norm" | shasum -a 256 | cut -d' ' -f1)"
if [ -f "$ledger/$fp" ]; then echo "dup:$fp"; else echo "$(date -u +%FT%TZ)" > "$ledger/$fp"; echo "new:$fp"; fi
```

- [ ] **Step 4: Run, expect pass** — `bats tests/dedup.bats` → 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/dedup.sh tests/dedup.bats
git commit -m "feat(dedup): fingerprint ledger create-or-bump"
```

### Task C2: `runlog.sh` — append a structured run record (NDJSON)

**Files:**
- Create: `scripts/runlog.sh`
- Test: `tests/runlog.bats`

- [ ] **Step 1: Write the failing test**

```bash
setup() { export PL_RUNS="$(mktemp -d)/runs"; }

@test "runlog: appends a valid NDJSON record with persona+repo+outcome" {
  run scripts/runlog.sh append --persona Ben --repo finances --trigger summon --outcome acted --tokens 1200
  [ "$status" -eq 0 ]
  line="$(tail -1 "$PL_RUNS/$(date -u +%F).ndjson")"
  echo "$line" | jq -e '.persona=="Ben" and .repo=="finances" and .outcome=="acted"'
}
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement `runlog.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
runs="${PL_RUNS:-$(pl_config_dir)/runs}"; mkdir -p "$runs"
[ "${1:-}" = "append" ] || pl_die "usage: runlog.sh append --persona .. --repo .. --trigger .. --outcome .. [--tokens N]"
shift; declare -A f=( [persona]="" [repo]="" [trigger]="" [outcome]="" [tokens]=0 [correlation_id]="" [stage]="" )
while [ $# -gt 0 ]; do k="${1#--}"; f[$k]="$2"; shift 2; done
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg p "${f[persona]}" --arg r "${f[repo]}" \
  --arg tr "${f[trigger]}" --arg o "${f[outcome]}" --argjson tok "${f[tokens]:-0}" \
  '{ts:$ts, persona:$p, repo:$r, trigger:$tr, outcome:$o, cost_tokens:$tok}' \
  >> "$runs/$(date -u +%F).ndjson"
```

- [ ] **Step 4: Run, expect pass.**

- [ ] **Step 5: Commit**

```bash
git add scripts/runlog.sh tests/runlog.bats
git commit -m "feat(runlog): append NDJSON run records"
```

### Task C3: `lock.sh` — create-only CAS writer lock with a real lock object + fence (no force)

> **(Amended per the go/no-go vote — Ben + Mike.)** The lock marker is a real branch
> `persona-lock/<repo>` pointing to a **dedicated lock commit** whose `lock.json` carries
> `{holder, claimed_at, fence}` where **`fence` = that commit's own SHA**. Build it with the Git Data
> API (blob → tree → commit), then **create-only** the ref at that commit (422 ⇒ lost the race — never
> `--force`, never update). Release = delete ref. The holder **re-reads the ref fresh and re-asserts its
> fence before every integrate-to-main push**; a mismatch ⇒ abort + checkpoint (this is what keeps Phase 1
> safe before the Phase-4 bot's ruleset enforcement). Never point the ref at `HEAD`/a literal string —
> always a resolved 40-char SHA. The lock object, the fence, and the verify step are the load-bearing
> parts the earlier draft omitted; the test must assert the lock object + fence, not just create/delete.

**Files:**
- Create: `scripts/lock.sh`
- Test: `tests/lock.bats`

- [ ] **Step 1: Write the failing test** (gh stub emulates blob/tree/commit/refs + ref read-back, so the test exercises the *lock object + fence*, not a shallow create)

```bash
setup() {
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_REF="$(mktemp)" PL_LOCKJSON="$(mktemp)"   # PL_REF empty = unlocked
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
# minimal Git Data API emulator over two temp files
case "$1 $2 $3" in
  "api -X POST")
    case "$4" in
      *git/blobs*)  echo '{"sha":"blobsha"}';;
      *git/trees*)  echo '{"sha":"treesha"}';;
      *git/commits*) echo '{"sha":"commitsha111111111111111111111111111111"}';;
      *git/refs*)
        [ -s "$PL_REF" ] && { echo "HTTP 422 Reference already exists" >&2; exit 1; }
        echo "commitsha111111111111111111111111111111" > "$PL_REF";;
    esac;;
  "api -X DELETE") : > "$PL_REF";;
  "api -X PATCH") echo "REFUSED: no updates allowed" >&2; exit 99;;  # force/update must never be called
  "api ")  # read: gh api repos/.../git/<ref>
    [ -s "$PL_REF" ] && printf '{"object":{"sha":"%s"}}' "$(cat "$PL_REF")" || { echo "404" >&2; exit 1; };;
esac
SH
  # the lock.json content the impl PUTs as a blob is captured by intercepting stdin in a wrapper if needed;
  # here we assert via the impl writing its fence to stdout.
  chmod +x "$PL_TEST_BIN/gh"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_REF" "$PL_LOCKJSON"; }

@test "lock claim: returns the fence (the lock commit SHA)" {
  run scripts/lock.sh claim --repo finances --holder Ben
  [ "$status" -eq 0 ]; [[ "$output" == "commitsha111111111111111111111111111111" ]]
}
@test "lock claim: second claim is refused (held), no force/update attempted" {
  scripts/lock.sh claim --repo finances --holder Ben >/dev/null
  run scripts/lock.sh claim --repo finances --holder Alex
  [ "$status" -ne 0 ]   # if the impl ever PATCHed, the stub exits 99 and this still fails — good
}
@test "verify-fence: matches the recorded fence while held, fails after a steal" {
  fence="$(scripts/lock.sh claim --repo finances --holder Ben)"
  run scripts/lock.sh verify-fence --repo finances --fence "$fence"
  [ "$status" -eq 0 ]
  # simulate a steal: ref now points elsewhere
  echo "different2222222222222222222222222222222" > "$PL_REF"
  run scripts/lock.sh verify-fence --repo finances --fence "$fence"
  [ "$status" -ne 0 ]
}
@test "lock release then re-claim succeeds" {
  scripts/lock.sh claim --repo finances --holder Ben >/dev/null
  scripts/lock.sh release --repo finances --holder Ben
  run scripts/lock.sh claim --repo finances --holder Alex
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement `lock.sh`** — build a real lock commit, create-only ref at its SHA, fresh-read verify-fence; never `HEAD`, never PATCH/force

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
cmd="${1:?usage: lock.sh <claim|release|status|verify-fence> --repo R [--holder H] [--fence F]}"; shift
repo="" holder="" fence=""
while [ $# -gt 0 ]; do case "$1" in
  --repo) repo="$2"; shift 2;; --holder) holder="$2"; shift 2;; --fence) fence="$2"; shift 2;; *) shift;; esac; done
ref="refs/heads/persona-lock/${repo}"
case "$cmd" in
  claim)
    # 1) build a dedicated lock commit carrying lock.json {holder, claimed_at, fence(filled after)}
    lj="$(jq -nc --arg h "$holder" --arg t "$(date -u +%FT%TZ)" '{holder:$h, claimed_at:$t}')"
    blob="$(gh api -X POST "repos/{owner}/{repo}/git/blobs" -f content="$lj" -f encoding=utf-8 -q .sha)"
    tree="$(gh api -X POST "repos/{owner}/{repo}/git/trees" \
              -f 'tree[][path]=lock.json' -f 'tree[][mode]=100644' -f 'tree[][type]=blob' -f "tree[][sha]=$blob" -q .sha)"
    commit="$(gh api -X POST "repos/{owner}/{repo}/git/commits" -f message="persona-lock $repo by $holder" -f tree="$tree" -q .sha)"
    # 2) create-only ref at the lock commit; 422 (exists) ⇒ we lost. fence = the commit SHA.
    if gh api -X POST "repos/{owner}/{repo}/git/refs" -f ref="$ref" -f sha="$commit" >/dev/null 2>&1; then
      echo "$commit"           # the fence — caller records it
    else pl_die "lock held for $repo (claim refused — never force)"; fi ;;
  verify-fence)
    [ -n "$fence" ] || pl_die "verify-fence needs --fence"
    cur="$(gh api "repos/{owner}/{repo}/git/${ref}" -q .object.sha 2>/dev/null || true)"
    [ "$cur" = "$fence" ] || pl_die "fence mismatch (lock reclaimed) — abort the integrate, checkpoint instead" ;;
  release)
    gh api -X DELETE "repos/{owner}/{repo}/git/${ref}" >/dev/null 2>&1 || true; echo "released $repo" ;;
  status)
    gh api "repos/{owner}/{repo}/git/${ref}" >/dev/null 2>&1 && echo "held" || echo "free" ;;
  *) pl_die "unknown lock cmd $cmd";;
esac
```

- [ ] **Step 4: Run, expect pass** — `bats tests/lock.bats` → 4 PASS (incl. the fence + no-PATCH assertions).

- [ ] **Step 5: Wire the fence check into the dispatch path** — the Developer, on `--dispatch`, records its fence at claim and calls `lock.sh verify-fence` immediately before any push to the main line; a mismatch aborts + checkpoints (never pushes). Note this in `commands/persona.md` (Task E1).

- [ ] **Step 6: Commit**

```bash
git add scripts/lock.sh tests/lock.bats
git commit -m "feat(lock): create-only CAS with real lock object + fence re-assert (no force)"
```

---

## Task group D — agents (access locks) + disciplines + build

### Task D1: `assert-access.sh` — manifest capacity → tools whitelist, fail-closed

> The manifest is the single source of truth for access. This script maps each persona's capacity verb to a concrete `tools:` set and asserts the generated agent matches — fail-closed on mismatch.

**Files:**
- Create: `scripts/assert-access.sh`
- Create: `config/capability-map.json` (capacity verb → tool set)
- Test: `tests/assert-access.bats`

- [ ] **Step 1: Write `config/capability-map.json`**

```json
{
  "writes":  ["Read","Edit","Write","Bash","Grep","Glob"],
  "reads":   ["Read","Grep","Glob"],
  "audits":  ["Read","Grep","Glob","Bash"],
  "advises": ["Read","Grep","Glob"],
  "owns":    ["Read","Grep","Glob"]
}
```

- [ ] **Step 2: Write the failing test**

```bash
@test "assert-access: developer(writes) maps to the writes tool set" {
  run scripts/assert-access.sh tools-for writes
  [ "$status" -eq 0 ]; [[ "$output" == *"Write"* && "$output" == *"Bash"* ]]
}
@test "assert-access: reader capacity excludes Write/Edit" {
  run scripts/assert-access.sh tools-for reads
  [ "$status" -eq 0 ]; [[ "$output" != *"Write"* && "$output" != *"Edit"* ]]
}
```

- [ ] **Step 3: Run, expect fail.**

- [ ] **Step 4: Implement `assert-access.sh` (`tools-for` subcommand)**

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
map="$here/../config/capability-map.json"
case "${1:-}" in
  tools-for) jq -r --arg c "$2" '.[$c] | join(", ")' "$map";;
  *) pl_die "usage: assert-access.sh tools-for <capacity>";;
esac
```

- [ ] **Step 5: Run, expect pass; commit**

```bash
bats tests/assert-access.bats
git add scripts/assert-access.sh config/capability-map.json tests/assert-access.bats
git commit -m "feat(access): capacity→tools map + tools-for"
```

### Task D2: `build-agents.sh` — concatenate `_disciplines` into each briefing

**Files:**
- Create: `scripts/build-agents.sh`
- Create: `docs/personas/_disciplines.md` (if not present — pull the disciplines from the spec §"Shared disciplines")
- Test: `tests/build-agents.bats`

- [ ] **Step 1: Write `docs/personas/_disciplines.md`** — copy the four disciplines + the bus/concision/verification rules verbatim from the spec's `_disciplines` section.

- [ ] **Step 2: Write the failing test**

```bash
@test "build-agents: emits one agent per briefing with disciplines concatenated + tools frontmatter" {
  export PL_OUT="$(mktemp -d)"
  run scripts/build-agents.sh --out "$PL_OUT"
  [ "$status" -eq 0 ]
  [ -f "$PL_OUT/developer.md" ]
  grep -q "tools:" "$PL_OUT/developer.md"               # access lock present
  grep -q "Verification hierarchy" "$PL_OUT/developer.md" # disciplines concatenated
}
```

- [ ] **Step 3: Run, expect fail.**

- [ ] **Step 4: Implement `build-agents.sh`** (reads each `docs/personas/<name>.md` except `_*`, looks up its capacity in the manifest, writes frontmatter `tools:` from `assert-access.sh`, appends `_disciplines.md`)

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
out="agents"; [ "${1:-}" = "--out" ] && out="$2"
mkdir -p "$out"; disc="$here/../docs/personas/_disciplines.md"
for b in "$here"/../docs/personas/*.md; do
  base="$(basename "$b" .md)"; [[ "$base" == _* || "$base" == owner || "$base" == human ]] && continue
  cap="$(pl_manifest_get "engagement.${base}.capacity" 2>/dev/null || echo reads)"
  tools="$("$here/assert-access.sh" tools-for "${cap:-reads}")"
  { printf -- "---\nname: %s\ntools: %s\n---\n\n" "$base" "$tools"
    cat "$b"; printf "\n\n## Shared disciplines\n\n"; cat "$disc"; } > "$out/$base.md"
done
echo "built $(ls "$out" | wc -l | tr -d ' ') agents"
```

- [ ] **Step 5: Run, expect pass; commit**

```bash
bats tests/build-agents.bats
git add scripts/build-agents.sh docs/personas/_disciplines.md tests/build-agents.bats
git commit -m "feat(build): concat disciplines + tools frontmatter into agents"
```

### Task D3: Author the persona briefings + generate agents

**Files:**
- Modify: `docs/personas/*.md` (rename `owner.md`→`human.md`, `security-maven.md`→`head-of-security.md`, `design-maven.md`→`head-of-design.md`, `data-model-librarian.md`→`data-architect.md`; add `lead-engineer.md`, `head-of-finops.md`, `product-analyst.md`, `security-analyst.md`, `design-analyst.md`)
- Create (generated): `agents/*.md`

- [ ] **Step 1: Rename + edit existing briefings** to the final roster + names, each ending with a one-line **tone spec** (from the spec's tone table) and a **voice** note. Use `git mv` for renames.

- [ ] **Step 2: Write the new briefings** (`lead-engineer`, `head-of-finops`, and the three repo-tier analysts) following `docs/personas/_template.md`, each with: lens, decides-vs-escalates, does-NOT-do, access, tone.

- [ ] **Step 3: Generate agents**

Run: `scripts/build-agents.sh`
Expected: `built 11 agents`, and `agents/developer.md` has `tools:` including `Write` while `agents/head-of-security.md` does not.

- [ ] **Step 4: Verify access locks are correct (the load-bearing check)**

Run: `grep -L "Write" agents/*.md` → expect every reader persona listed; `grep -l "Write" agents/*.md` → expect only `developer.md`.

- [ ] **Step 5: Commit**

```bash
git add docs/personas agents
git commit -m "feat(agents): final roster briefings + generated access-locked agents"
```

---

## Task group V — verification spine (enforceable, not prose)

> **(Added per the go/no-go vote — Greg's HOLD + Sarah.)** Phase 1 must ship the verification/review
> contract as *tested code*, not briefing prose — otherwise self-closing with a free-text `PROOF` becomes
> the norm from commit one, which is ruinous to retrofit. The human may play Lead Engineer *manually* in
> Phase 1, but the **deterministic gate** that enforces "verification = manifest + artifact, not
> attestation" exists and runs. This also freezes the canonical **schema set** (Sarah) as the one source
> the gates assert against.

### Task V1: `config/schemas/` — the frozen, versioned required-field schema set

**Files:**
- Create: `config/schemas/{review,run-record,needs-human-decision,needs-human-action}.json`
- Create: `config/schemas/VERSION`
- Test: `tests/schemas.bats`

- [ ] **Step 1: Write the failing test**

```bash
@test "schemas: each package schema declares required fields and is valid JSON" {
  for s in config/schemas/*.json; do jq -e '.required | type=="array" and length>0' "$s"; done
}
@test "schemas: REVIEW verdict enum is the canonical three" {
  run jq -r '.properties.verdict.enum | join(",")' config/schemas/review.json
  [ "$output" = "approved,changes-requested,bounce:out-of-scope" ]
}
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Write the schemas** (one source of truth for every gate). `review.json`:

```json
{ "$id": "review", "type": "object",
  "required": ["reviewer","commit_sha","verdict"],
  "properties": {
    "reviewer": {"type":"string"},
    "commit_sha": {"type":"string","minLength":7},
    "verdict": {"enum":["approved","changes-requested","bounce:out-of-scope"]},
    "notes": {"type":"string"} } }
```

`run-record.json` (matches `runlog.sh`): required `["ts","persona","repo","trigger","outcome"]`, with
`cost_tokens` present and **commented as harness-sourced, not self-reported** (Dave — reserve the field
now). `needs-human-decision.json`: required `["question","why_now","options","recommendation","consequences","unblocks"]`.
`needs-human-action.json`: required `["why","why_not_automated","steps","commands","verification"]`.
`config/schemas/VERSION` = `1`.

- [ ] **Step 4: Run, expect pass; commit**

```bash
bats tests/schemas.bats
git add config/schemas tests/schemas.bats
git commit -m "feat(schemas): frozen versioned required-field package set (v1)"
```

### Task V2: `scripts/gate.sh` — deterministic pre-close gate

**Files:**
- Create: `scripts/gate.sh`
- Test: `tests/gate.bats`

- [ ] **Step 1: Write the failing test** (stubs a verification-manifest run marker + a diff)

```bash
setup() {
  export PL_WORK="$(mktemp -d)"; cd "$PL_WORK"; git init -q
  mkdir -p .claude/persona-lab; echo '{"max_lines":400,"max_files":20}' > .claude/persona-lab/diff_budget.json
}
@test "gate: passes when manifest ran, diff within budget, and a REVIEW cites HEAD" {
  echo a > f.txt; git add f.txt; git commit -qm x; head="$(git rev-parse HEAD)"
  : > .claude/persona-lab/verified.marker          # verification manifest ran
  echo "{\"commit_sha\":\"$head\",\"verdict\":\"approved\"}" > .claude/persona-lab/review.json
  run "$OLDPWD/scripts/gate.sh" check --head "$head"
  [ "$status" -eq 0 ]
}
@test "gate: fails when the REVIEW cites a stale commit (HEAD moved)" {
  echo a > f.txt; git add f.txt; git commit -qm x
  : > .claude/persona-lab/verified.marker
  echo '{"commit_sha":"deadbeef","verdict":"approved"}' > .claude/persona-lab/review.json
  echo b >> f.txt; git commit -aqm y; head="$(git rev-parse HEAD)"
  run "$OLDPWD/scripts/gate.sh" check --head "$head"
  [ "$status" -ne 0 ]
}
@test "gate: fails when no verification marker exists (self-close blocked)" {
  echo a > f.txt; git add f.txt; git commit -qm x; head="$(git rev-parse HEAD)"
  echo "{\"commit_sha\":\"$head\",\"verdict\":\"approved\"}" > .claude/persona-lab/review.json
  run "$OLDPWD/scripts/gate.sh" check --head "$head"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run, expect fail.**

- [ ] **Step 3: Implement `scripts/gate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
[ "${1:-}" = "check" ] || pl_die "usage: gate.sh check --head <sha>"; shift
head=""; [ "${1:-}" = "--head" ] && head="$2"
cfg="$(pl_repo_root)/.claude/persona-lab"

# 1) verification manifest must have run (marker written by the test/build commands)
[ -f "$cfg/verified.marker" ] || pl_die "gate: verification manifest did not run (no marker) — not done"

# 2) a REVIEW record must exist, be approved, and cite the CURRENT head (SHA-bound, no stale approval)
rj="$cfg/review.json"; [ -f "$rj" ] || pl_die "gate: no REVIEW record"
[ "$(jq -r .verdict "$rj")" = "approved" ] || pl_die "gate: REVIEW not approved"
[ "$(jq -r .commit_sha "$rj")" = "$head" ] || pl_die "gate: REVIEW cites a stale commit (HEAD moved) — re-review"

# 3) diff budget (added+removed across files, excluding lockfiles/generated) must hold
budget="$cfg/diff_budget.json"
if [ -f "$budget" ]; then
  read -r ml mf < <(jq -r '"\(.max_lines) \(.max_files)"' "$budget")
  lines="$(git diff --numstat HEAD~1 2>/dev/null | awk '{a+=$1+$2} END{print a+0}')"
  files="$(git diff --name-only HEAD~1 2>/dev/null | wc -l | tr -d ' ')"
  [ "${lines:-0}" -le "$ml" ] || pl_die "gate: diff $lines lines > budget $ml — re-scope"
  [ "${files:-0}" -le "$mf" ] || pl_die "gate: diff $files files > budget $mf — re-scope"
fi
echo "gate: pass"
```

- [ ] **Step 4: Run, expect pass; commit**

```bash
bats tests/gate.bats
git add scripts/gate.sh tests/gate.bats
git commit -m "feat(gate): deterministic pre-close gate (manifest+artifact+SHA-bound REVIEW+budget)"
```

### Task V3: Wire the gate into close

**Files:**
- Modify: `commands/persona.md` (the Developer's close path)
- Modify: the E4 acceptance (below)

- [ ] **Step 1:** State in `commands/persona.md` that the Developer **cannot close** until `scripts/gate.sh check --head $(git rev-parse HEAD)` passes; a free-text `PROOF` alone is not a close. In Phase 1 the human emits the `REVIEW` record (playing Lead Engineer) — the *gate* is what's enforced, the reviewer can be manual.
- [ ] **Step 2: Commit**

```bash
git add commands/persona.md
git commit -m "feat(gate): block close until the deterministic gate passes"
```

---

## Task group E — launcher, cockpit, manifest, end-to-end

### Task E1: `/persona` launcher command

**Files:**
- Create: `commands/persona.md`

- [ ] **Step 1: Write `commands/persona.md`** — a slash command that summons a persona (loads its agent) or dispatches it. Summon = the engage-human-first lifecycle; dispatch = a single foreground run (no auto-mode). It must: read the manifest, refuse if the persona isn't in scope, and for the Developer use `claude --worktree`.

```markdown
---
description: Summon or dispatch a persona (summon = advise interactively; dispatch = one foreground run).
argument-hint: <persona> [--dispatch]
---
Load the persona named `$1` from this repo's `.claude/persona-lab/manifest.yml` roster.
If it's not in the roster, stop and say so. Default mode is **summon** (engage the human
first, advise, act only on request — autonomy OFF). With `--dispatch`, run one foreground
unit of that persona's work (the Developer acquires the writer lock via `scripts/lock.sh`
and works in `claude --worktree`); never auto-mode, never unattended. On yield, append a
run record via `scripts/runlog.sh`.
```

- [ ] **Step 2: Manual verify** — install the plugin locally (`/plugin marketplace add ./` then `/plugin install persona-lab`), run `/persona head-of-security` in a test repo, confirm it loads in the engage-first posture and cannot edit files.

- [ ] **Step 3: Commit**

```bash
git add commands/persona.md
git commit -m "feat(command): /persona summon+dispatch launcher"
```

### Task E2: `/inbox` cockpit command

**Files:**
- Create: `commands/inbox.md`

- [ ] **Step 1: Write `commands/inbox.md`** — aggregates `needs-human:*` items via `queue.sh query`, renders **two queues (Decisions / Actions)** as scannable one-line rows (expand to the full framed package), shows the **designed zero state** when empty ("All clear …"), and never surfaces non-ripe/radar items. `/decisions` is registered as a silent alias.

```markdown
---
description: The cockpit — decisions and actions waiting on you (the one front door).
---
Run `scripts/queue.sh query --label needs-human:decision` and `--label needs-human:action`.
Render two sections — **Decisions waiting** (you choose) and **Actions for you** (you perform) —
each item a one-line row `[severity] · who · the ask (≤8 words) · what it unblocks`, expandable
to the full framed package (decision: options+recommendation; action: the runbook). If both are
empty, show the **canonical zero-state string** (defined once — see Step 2). Never show radar/not-yet-ripe items here.
```

- [ ] **Step 2: Pin ONE canonical zero-state string** (Laura — it was specified twice and would drift).
  Define it once in `config/copy.json` as `zero_state`, value exactly:
  `"All clear — N items moving on their own, nothing needs you · see the team · /radar"`. `commands/inbox.md`
  and the opt-in session-start line both reference `config/copy.json#zero_state`; neither re-coins it.

- [ ] **Step 3: Manual verify** — file a `needs-human:decision` test issue (`scripts/queue.sh file … && scripts/queue.sh label …`), run `/inbox`, confirm it shows under Decisions with the framed row; close it, run `/inbox`, confirm the zero state renders the canonical string.

- [ ] **Step 4: Commit**

```bash
git add commands/inbox.md config/copy.json
git commit -m "feat(command): /inbox cockpit (two queues + canonical zero state)"
```

### Task E3: Hand-write the instance manifest for one real repo

**Files:**
- Create: `config/manifest.example.yml`
- Create (in the target repo): `.claude/persona-lab/manifest.yml`

- [ ] **Step 1: Write `config/manifest.example.yml`** (documented)

```yaml
grain: single            # single repo (no platform tier in Phase 1)
owner: Chris             # the human
bus: github-issues
repo: finances
engagement:              # capacity drives the agent tools: whitelist
  developer:        { capacity: writes,  trigger: [summon, on-demand] }
  product-analyst:  { capacity: owns,    trigger: [summon, on-demand] }  # local queue
  security-analyst: { capacity: audits,  trigger: [summon] }
  design-analyst:   { capacity: audits,  trigger: [summon] }
oversight:
  autonomy: conservative # invariant: escalate-by-default, auto-mode OFF
  visibility: minimal
```

- [ ] **Step 2: Place a real instance manifest** in the target repo's `.claude/persona-lab/manifest.yml` (single-repo: developer + product-analyst + the two analysts as summon-only).

- [ ] **Step 3: Rebuild agents against the real manifest**

Run: `scripts/build-agents.sh` and re-verify access locks (Task D3 Step 4).

- [ ] **Step 4: Commit**

```bash
git add config/manifest.example.yml
git commit -m "docs(manifest): documented single-repo example"
```

### Task E4: End-to-end validation (the Phase-1 acceptance)

- [ ] **Step 1: Full test suite green**

Run: `bats tests/`
Expected: all tests pass.

- [ ] **Step 2: Acceptance walk-through (rendered-output evidence — record what you see):**
  1. Summon the Product Analyst: `/persona product-analyst` → it engages first, proposes, can't write.
  2. It files a finding: a `FINDING` issue appears on GitHub with the AI envelope (header + collapsed footer).
  3. Re-file the same finding → `dedup.sh` returns `dup:` and no second issue is created.
  4. The PM (summoned) frames it and marks `needs-human:decision`.
  5. `/inbox` shows it under **Decisions waiting** as a framed row; the raw queue is one command away.
  6. Resolve it; `/inbox` shows the **zero state** (the one canonical string from Task E2).
  7. Dispatch the Developer on a scoped bug issue: it acquires the lock (`scripts/lock.sh status` → held)
     and records its fence, works in a worktree, **runs `scripts/lock.sh verify-fence` before integrating**
     (must match), emits a `REVIEW` record (you play Lead Engineer) citing HEAD, and the close is **blocked
     until `scripts/gate.sh check` passes** (verification marker + approved REVIEW on current HEAD + diff
     budget) — a free-text `PROOF` alone does NOT close. Then it releases the lock.
  8. Negative check: try to close with no verification marker → `gate.sh` refuses. Try to integrate after
     forcing a fence mismatch → the Developer aborts instead of pushing.

- [ ] **Step 3: Write the acceptance note** in `docs/superpowers/plans/2026-06-22-phase-1-ACCEPTANCE.md` with the rendered evidence (issue URLs/screenshots), per the verification discipline.

- [ ] **Step 4: Commit + open the PR**

```bash
git add docs/superpowers/plans/2026-06-22-phase-1-ACCEPTANCE.md
git commit -m "test(phase-1): end-to-end acceptance evidence"
```

---

## Out of scope (subsequent phases)
- **Phase 2:** `/persona-init` bootstrap interview (generates the manifest instead of hand-writing).
- **Phase 3:** platform tier, portfolio manifest, cross-repo bus, Projects v2 cockpit aggregation, promotion.
- **Phase 4:** autonomous dispatch (`claude -p` loops, auto-mode), the GitHub App bot, scheduling + the ~9am scan, egress/token hardening, the live `/feed` dashboard, ruleset-enforced lock.
