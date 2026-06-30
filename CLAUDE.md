# persona-lab — working rules for the mainline assistant

persona-lab is operated by a **named team of AI personas** running a GitHub-Issues bus.
In this repo the mainline assistant (you) is **not** the team and **not** its orchestrator.

## You do not cast, assign, dispatch, or close — the cycle + PM + RACI do
- **Never hand-pick which persona does a task or weighs in on a question, and never default
  to a favorite (e.g. reaching for the Enterprise Architect every time).** Who works an issue
  is set by the dispatch cycle off a `persona:<slug>` label; who is *accountable* comes from
  the **RACI** (owned by Remy, the Delivery Manager); who gets *consulted* is **Sarah (PM)**
  coordinating off that RACI. Route every "who should do/decide/weigh-in?" to Sarah + the RACI
  — do not choose it yourself. (This is the recurring "handoff mistake" — stop it.)
- **When you bring a persona in, don't script their task.** Give them the full, accurate
  situation — including what's already decided or built — and ask what their role requires;
  let them decide and act. A prescribed to-do list makes them your executor, not the
  role-owner; under-briefing them produces stale or wrong calls.
- **Never close an issue by hand.** A close is the accountable persona's act (PM acceptance),
  posted as an enveloped record on the bus citing the proof, with no self-close (ADR-0001) —
  never a bare `gh issue close` or an orchestrator close.
- **Don't relay persona work as chat.** A persona's output lands on the bus as an enveloped,
  attributed record via `scripts/queue.sh` — not as your prose summary.
- **Adding/changing a role is the founder's call.** Personas propose; the founder decides.

## Bus hygiene: comment, don't spawn issues (NON-NEGOTIABLE)
- The tracker holds **units of work**, not a log for every observation. **Default to COMMENTING**
  on the relevant existing issue or PR — findings, review verdicts, QA/design sign-offs, follow-ups,
  discussion, and steers are comments on their parent (the PR, the issue, or the epic).
- **Open a NEW issue ONLY for genuinely distinct, standalone work** with its own What/Why/Acceptance.
- **No proxy issues.** A PR review is dispatched against the PR (`triage-reviews.sh`) and lands as a
  comment + gate label on it — never a "Review PR #N" tracking issue. Applies to the harness and
  every persona.

## Routing must be visible on the issues
- Every actionable issue carries `persona:<slug>` + `state:ready` + `priority:pN` — that *is*
  the routing, visible on the issue, not in anyone's head. Sarah applies the labels per Remy's
  RACI during triage; `raci.sh classify` (#45) will derive them from work-type automatically.

## Gates (before merge)
- Code review = **Greg (Lead Engineer)**. QA sign-off on any `tests/` or `scripts/` change =
  **Priya (Head of QA)**, with a mutation proof. Anything visual = **Laura (Head of Design)**.
  The human is never the code reviewer.

## Naming / identity
- Ground user-facing names in real practitioner vocabulary (plain, easy to pronounce).
  **Do not catalog persona race or age anywhere** — identity is name + avatar only; new
  avatars come from `assets/avatar-bench/`.
