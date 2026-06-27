# Phase 2 — bootstrap (`/persona-init`) Implementation Plan

> **For agentic workers:** use superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** Make persona-lab installable: a `/persona-init` interview that asks the operating questions, generates the instance config (manifest + names), provisions labels, and builds the agents — so a fresh repo goes from plugin-installed to live.

**Architecture:** Deterministic generators in tested bash (`init.sh` writes the manifest from flags; `assign-names.sh` picks distinct names from the pools), driven by a `/persona-init` slash command that runs the interview, calls the generators + `setup-labels.sh` + `build-agents.sh`, and reports ready. Single-repo grain only (platform tier = Phase 3).

**Tech stack:** bash 3.2, bats, jq, yq, gh. Builds on Phase 1 scripts.

**Reference:** spec Appendix A (interview questions); `config/manifest.example.yml`; `docs/personas/_name-pools.md`.

---

## File structure
```
scripts/init.sh           generate .claude/persona-lab/manifest.yml from flags (idempotent)
scripts/assign-names.sh   resolve each role's one fixed name from the roster
commands/persona-init.md  the bootstrap interview (drives the generators)
tests/init.bats           init.sh tests
tests/assign-names.bats   assign-names.sh tests
```

## Task P2A-1: `scripts/init.sh` — manifest generator
**Files:** Create `scripts/init.sh`, `tests/init.bats`

- [ ] **Step 1: failing test** `tests/init.bats`
```bash
setup() { export PL_CONFIG_DIR="$(mktemp -d)"; }
teardown() { rm -rf "$PL_CONFIG_DIR"; }
@test "init: writes a yq-valid single-repo manifest with conservative oversight" {
  run scripts/init.sh --repo finances --owner Chris --personas "developer:writes,product-analyst:owns"
  [ "$status" -eq 0 ]
  mf="$PL_CONFIG_DIR/manifest.yml"; [ -f "$mf" ]
  [ "$(yq -r .grain "$mf")" = "single" ]
  [ "$(yq -r .repo "$mf")" = "finances" ]
  [ "$(yq -r .oversight.autonomy "$mf")" = "conservative" ]
  [ "$(yq -r '.engagement.developer.capacity' "$mf")" = "writes" ]
}
@test "init: refuses to clobber an existing manifest without --force" {
  scripts/init.sh --repo a --owner x --personas "developer:writes" >/dev/null
  run scripts/init.sh --repo b --owner y --personas "developer:writes"
  [ "$status" -ne 0 ]
}
```
- [ ] **Step 2:** run, expect fail.
- [ ] **Step 3: implement `scripts/init.sh`**
```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$here/lib/common.sh"
repo="" owner="" personas="" force=0
while [ $# -gt 0 ]; do case "$1" in
  --repo) repo="$2"; shift 2;; --owner) owner="$2"; shift 2;;
  --personas) personas="$2"; shift 2;; --force) force=1; shift;; *) pl_die "init: unknown arg $1";; esac; done
[ -n "$repo" ] && [ -n "$owner" ] && [ -n "$personas" ] || pl_die "init: --repo --owner --personas required"
case "$repo" in *[!A-Za-z0-9_.-]*) pl_die "init: invalid repo '$repo'";; esac
cfg="$(pl_config_dir)"; mf="$cfg/manifest.yml"; mkdir -p "$cfg"
[ -f "$mf" ] && [ "$force" -eq 0 ] && pl_die "init: $mf exists (use --force)"
{
  echo "grain: single"
  echo "owner: $owner"
  echo "bus: github-issues"
  echo "repo: $repo"
  echo "engagement:"
  IFS=','; for p in $personas; do
    name="${p%%:*}"; cap="${p##*:}"
    case "$name" in *[!a-z-]*) pl_die "init: invalid persona '$name'";; esac
    printf '  %s: { capacity: %s }\n' "$name" "$cap"
  done; unset IFS
  echo "oversight:"
  echo "  autonomy: conservative"
  echo "  visibility: minimal"
} > "$mf"
yq . "$mf" >/dev/null || pl_die "init: produced invalid yaml"
echo "wrote $mf"
```
- [ ] **Step 4:** run, expect pass; **Step 5:** `git add scripts/init.sh tests/init.bats && git commit -m "feat(init): manifest generator"`

## Task P2B-1: `scripts/assign-names.sh` — distinct names from pools
**Files:** Create `scripts/assign-names.sh`, `tests/assign-names.bats`

- [ ] **Step 1: failing test**
```bash
@test "assign-names: returns a name from the developer pool" {
  run scripts/assign-names.sh developer finances
  [ "$status" -eq 0 ]; [ -n "$output" ]
  grep -qiw "$output" docs/personas/_name-pools.md
}
@test "assign-names: deterministic per (persona,repo)" {
  a="$(scripts/assign-names.sh developer finances)"; b="$(scripts/assign-names.sh developer finances)"
  [ "$a" = "$b" ]
}
```
- [ ] **Step 2:** run, expect fail.
- [ ] **Step 3: implement** — read the persona's pool line from `_name-pools.md` (the row after the `### <Persona>` header, names separated by `·`), pick deterministically by `sha256(persona|repo) mod N`. bash 3.2; handle the platform singletons (fixed names) vs repo pools. If a persona has no pool (platform singleton), return its fixed name from the platform table. Keep it real — parse the markdown pools.
- [ ] **Step 4:** run, expect pass; **Step 5:** commit `feat(init): deterministic name assignment from pools`

## Task P2C-1: `commands/persona-init.md` — the interview
**Files:** Create `commands/persona-init.md`

- [ ] **Step 1:** write the slash command. Frontmatter `description: Bootstrap persona-lab in this repo (interview → config → live).` Body: run the Appendix-A interview ONE question at a time (grain — Phase 2 = single only; owner; repo [default: current repo name]; which disciplines/personas in scope [default minimal: developer + product-analyst]; per-persona trigger; daily budget ceiling; **state — don't ask — that autonomy is conservative + visibility minimal by default, no auto-mode**; propose names per persona via `assign-names.sh`, human may override). Then: call `scripts/init.sh` with the collected answers, `scripts/assign-names.sh` for names, `scripts/setup-labels.sh`, `scripts/build-agents.sh`; verify the access-lock invariant (`grep` only developer has Write); report "ready — N personas, run /persona <name> or /inbox".
- [ ] **Step 2:** sanity check the command file; `bats tests/` still green.
- [ ] **Step 3:** commit `feat(command): /persona-init bootstrap interview`

## Acceptance (P2D)
- [ ] Run `scripts/init.sh` + `assign-names.sh` end-to-end in a temp `PL_CONFIG_DIR`; confirm a yq-valid manifest with assigned names, conservative oversight, and that `build-agents.sh` against it yields correct access locks. Full suite green. Commit acceptance note.

## Out of scope
- Platform-tier bootstrap / promotion (Phase 3). Autonomous dispatch (Phase 4).
