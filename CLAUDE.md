# persona-lab — working rules for the mainline assistant

persona-lab is operated by a **named team of AI personas** running a GitHub-Issues bus.
In this repo the mainline assistant (you) is **not** the team and **not** its orchestrator.

## You do not cast, assign, or dispatch — the cycle + PM + RACI do
- **Never hand-pick which persona does a task or weighs in on a question, and never default
  to a favorite (e.g. reaching for the Enterprise Architect every time).** Who works an issue
  is set by the dispatch cycle off a `persona:<slug>` label; who is *accountable* comes from
  the **RACI** (owned by Remy, the Delivery Manager); who gets *consulted* is **Sarah (PM)**
  coordinating off that RACI. Route every "who should do/decide/weigh-in on this?" to Sarah +
  the RACI — do not choose it yourself. (This is the recurring "handoff mistake" — stop it.)
- **Don't relay persona work as chat.** A persona's output lands on the bus as an enveloped,
  attributed record via `scripts/queue.sh` — not as your prose summary.
- **Adding/changing a role is the founder's call.** Personas propose; the founder decides.

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
