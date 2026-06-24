# Phase 3 — acceptance evidence (platform tier, unit-level)

Run 2026-06-24. Full suite: **46/46 bats green**.

- `init.sh` (single, finances) → `promote.sh --add-repo travel` → `grain: platform`, `repos: [finances, travel]` (engagement + conservative oversight preserved); idempotent re-add; invalid repo name rejected.
- `queue.sh <verb> --repo <owner/name>` reaches the `gh` call (cross-repo bus addressing); current-repo behavior unchanged when `--repo` absent.
- Docs: platform manifest example + promotion path in `/persona-init`.

**Deferred (real boundary):** live cross-repo coordination (expand→migrate→contract across ≥2 real repos), Projects v2 cross-repo board aggregation. These need an actual portfolio (≥2 repos) to build + verify meaningfully.
