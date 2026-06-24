# Phase 1 — acceptance evidence (live, against ChristopherSchubert/persona-lab)

Run 2026-06-24. Self-contained plugin core exercised end-to-end against the real GitHub repo.
Full unit suite: **27/27 bats green**. Access-lock invariant: only `developer` carries Write/Edit.

## Bus (real GitHub Issues)
- **Filed** issue [#1](https://github.com/ChristopherSchubert/persona-lab/issues/1) via `queue.sh file`
  (persona Nina · Product Analyst) — the AI comment envelope rendered correctly: header
  `🤖 **Nina** (persona-lab Team · Product Analyst) · FINDING`, body, collapsed `AI persona — not the human` footer.
- **Dedup**: re-filing the identical finding returned `new:…` then `dup:…` (report-by-exception — no duplicate issue).
- **Admit + query**: `queue.sh label 1 --add needs-human:decision` then `queue.sh query --label needs-human:decision`
  returned issue #1 (the `/inbox` Decisions-queue input). [GitHub label index is eventually consistent — a re-query resolves it.]

## Writer lock (live, create-only CAS + fence, no force)
- `lock.sh claim --repo persona-lab --holder Sam` → fence `c39dfc7…`; remote ref `refs/heads/persona-lock/persona-lab` created at that SHA.
- `verify-fence` matched (safe to integrate); a **second claim was refused** ("claim refused — never force"); `release` deleted the ref; status returned to `free`.

## Close gate (deterministic, blocks attestation)
- No verification marker → **blocked** ("verification manifest did not run — not done").
- Marker + approved `REVIEW` citing current HEAD → **pass**.
- `REVIEW` citing a stale commit → **blocked** ("REVIEW cites a stale commit — re-review").

## Gap found & fixed during acceptance
`label --add` initially failed — GitHub labels must pre-exist. Added `scripts/setup-labels.sh`
(idempotent provisioning of the canonical label set: `needs-human:*`, `blocked-by:*`, `trust:external`,
`quarantine`, `origin:external`) and ran it. Label provisioning belongs in the Phase-2 bootstrap.

## Follow-ups (non-blocking)
- `runlog.sh` needs an `--id`/update path for one-record-per-wake billing attribution.
- Autonomous bus access for read-only personas (Phase 4; Phase 1 mediates via the launcher).
- Lock release on interrupted exit is best-effort until the Phase-4 watchdog.
