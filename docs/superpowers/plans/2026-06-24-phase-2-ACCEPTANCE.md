# Phase 2 — acceptance evidence (bootstrap)

Run 2026-06-24. Full suite: **32/32 bats green**.

Bootstrap generate path verified end-to-end (isolated `PL_CONFIG_DIR`, temp agent out):
- `scripts/init.sh --repo demo-app --owner Chris --personas "developer:writes,product-analyst:owns,security-analyst:audits"` → yq-valid manifest, `oversight.autonomy: conservative`, `visibility: minimal` (no auto-mode; not asked).
- `scripts/assign-names.sh` → distinct repo-tier names (developer→Nancy, product-analyst→Ines, security-analyst→Hana), fixed platform singletons (product-manager→Sarah, head-of-finops→Dave); deterministic per (persona,repo).
- `scripts/build-agents.sh` against the generated manifest → access locks correct: `developer` = Read,Edit,Write,Bash,Grep,Glob; readers Read,Grep,Glob (+Bash for auditors). **Invariant holds: only developer has Write/Edit.**
- `commands/persona-init.md` orchestrates init → assign-names → setup-labels → build-agents, states conservative-by-default governance, and verifies the access lock before declaring ready.

Result: a fresh repo can go plugin-installed → live via `/persona-init`. (Live interactive run of the slash command is a human step; the generators it calls are proven here.)
