# Shared disciplines

Rules that apply to every persona, regardless of role or tier.

## Verification hierarchy

Deterministic rules beat everything. If a check can be expressed as a script or a schema assertion,
run it — do not substitute prose inspection. When the answer is deterministic, do not call an LLM to
produce it.

For output that cannot be checked programmatically, verify against **rendered / real behavior** — the
actual page, the running command's stdout, the real API response. Visual/rendered checks beat
LLM-as-judge; LLM-as-judge is the last resort, not the default.

"Looks done" is not done. A claim of completion requires:
- **Manifest**: the artifact exists where it's supposed to (file path, issue state, migration
  applied).
- **Cited artifact**: a direct pointer to the thing (file path + line, issue URL, screenshot path),
  not a paraphrase of what it says.
- **Every reference resolves**: any artifact you point the human at — an issue, comment, PR, file,
  or screenshot — must be an actual clickable link (full URL) or an openable `path:line` in the same
  message. Never tell the human to "look at", "see", or "scroll to" something that isn't linked
  right there. If you can't link it, show it inline or don't reference it.

Attestation ("I verified it") without cited artifact evidence fails the hierarchy. Every persona
closes work with proof, not permission.

## Context hygiene

The conversation window is scratch space — it resets. Files and issues are memory.

- Record decisions, findings, and handoffs to issues (with the correct record type header) rather
  than assuming the next session will have window context.
- Compact aggressively. Keep always-loaded context short; prefer narrow reads (targeted grep,
  specific file sections) over broad loads.
- Note-take incrementally during long tasks — don't rely on reconstructing state from a long
  thread at close time.
- Before starting any non-trivial task, confirm what is already known (open issues, existing files,
  prior decisions) rather than re-deriving from first principles.

## Fan-out economics

Sub-agent fan-out costs roughly 15× the tokens of serialized work (context duplication + merge
overhead). It is not free concurrency.

Fan out only when all three conditions hold:
1. **Bounded**: the sub-tasks are a known, finite set.
2. **Independent**: no sub-task's output is needed by another before the merge.
3. **High-value**: the value of parallelism (speed, coverage) clearly outweighs the token cost.

When in doubt, serialize on the queue. A fast sequential scan is almost always cheaper than a
fan-out followed by a contested merge. Reserve fan-out for cases where the wall-clock difference
genuinely matters (e.g., independent audits that would otherwise gate each other serially).

## Concision

Draft for the reader who is short on time, not the writer who wants to be thorough.

**Necessary completeness**: include everything the reader needs to act; omit everything else.
**Reader-tested**: after drafting, ask "would a reader who didn't write this know what to do?" — if
yes, it's done. If not, add the missing piece; don't add more words around it.

Not minimal words. Not exhaustive coverage. The right words for the right reader.

## Bus discipline

All cross-persona communication flows through **typed records** on the issue bus. Personas do not
converse in-thread; they write records that stand alone.

**Record types:**
- `FINDING` — an observed fact, anomaly, or risk.
- `PROPOSAL` — a suggested course of action (not yet a decision).
- `DECISION` — a resolved direction, with rationale and rejected alternatives noted.
- `HANDOFF` — a unit of work passed to another persona or the queue.
- `PROOF` — evidence that acceptance criteria were met (cited artifact required).
- `REVIEW` — structured feedback on a proposal or artifact.
- `BLOCKED` — a stall point with the specific blocker named and the unblocking ask stated.

**Comment envelope format:**

Every bus comment opens with a header line and closes with a collapsed footer:

```
🤖 **Name** (tier · role) · TYPE

<body — structured, cited, no conversational filler>

<details><summary>Model / run metadata</summary>
model: <model-id>  run: <ISO-timestamp>  tokens: <n>
</details>
```

The header identifies who wrote it, what capacity they hold, and what record type this is.
The footer is collapsed by default so it doesn't crowd the human-readable view.

Personas do not reply to each other's comments inline. If a FINDING needs a PROPOSAL in response,
file a new comment (or a new issue) with the correct type header. The bus is append-only; threads
are not conversations.
