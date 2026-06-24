# Phase 3 — platform tier Implementation Plan (testable core; live cross-repo acceptance deferred)

> superpowers:subagent-driven-development. Builds on Phases 1–2.

**Goal:** Support a platform spanning multiple repos: a portfolio manifest, promotion from single→platform, and cross-repo bus addressing — built + unit-tested now; live cross-repo coordination (expand/migrate/contract) verified once a 2nd real repo exists.

**Scope note:** the *mechanics* (manifest, promote, --repo targeting) are buildable/testable single-repo with fixtures. Live multi-repo acceptance is the deferred boundary (needs ≥2 real repos + gh).

## Task P3A: cross-repo bus addressing — `queue.sh --repo <owner/name>`
**Files:** modify `scripts/queue.sh`, `tests/queue.bats`
- [ ] Add an optional `--repo <owner/name>` to every verb that, when present, passes `--repo <owner/name>` to the `gh issue ...` call (gh natively supports `--repo`); when absent, current-repo behavior is unchanged. Test (extend the gh stub) that `--repo o/r` reaches the `gh` call. Commit `feat(queue): cross-repo --repo targeting`.

## Task P3B: platform manifest + `scripts/promote.sh`
**Files:** create `scripts/promote.sh`, `tests/promote.bats`
- [ ] `promote.sh --add-repo <name>` converts a `grain: single` manifest → `grain: platform` with a `repos: [<orig>, <name>]` list (idempotent; preserves engagement + oversight; validates repo name). For an already-platform manifest, appends the repo. yq-valid output. TDD (fixtures via `PL_CONFIG_DIR`). Commit `feat(promote): single→platform manifest promotion`.

## Task P3C: platform-tier roster note + docs
**Files:** modify `config/manifest.example.yml` (add a commented platform example), `commands/persona-init.md` (note promotion path)
- [ ] Add a documented platform-shape example (grain: platform, repos, platform seniors own cross-app artifacts, repo-tier per member). Note `/persona promote` (or `scripts/promote.sh`) as the path. Commit.

## Acceptance (P3D, partial — unit only)
- [ ] Full suite green; promote a fixture single→platform and confirm yq-valid platform manifest; queue.sh --repo reaches gh. **Live cross-repo coordination acceptance deferred to a 2nd real repo.** Commit acceptance note.

## Out of scope
- Live cross-repo expand/migrate/contract execution (needs ≥2 repos). Projects v2 cross-repo board aggregation. Phase 4 (autonomous dispatch).
