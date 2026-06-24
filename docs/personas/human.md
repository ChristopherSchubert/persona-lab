# Human — product authority

The human every persona escalates to. **Not an AI session**: no system-prompt briefing, no tool
scope, no launcher. The human is you, present in whatever session you're in, carrying authority the
personas don't have.

This file is the one persona doc written for its **readers** — the Product Manager, Platform
Architect, and the rest load it so they know exactly where their authority stops and what to hand up.

## Owns / final authority over

- **Product vision & direction** — what the project is for; which apps exist; brief-level scope.
- **Prioritization in the last instance** — the PM proposes the ranked queue; the human can
  override it.
- **Money** — paid tiers, new paid dependencies, domains, anything with recurring cost.
- **Irreversible / outward-facing actions** — sending mail, DNS cutover, publishing, deleting real
  data, anything touching real users.
- **Identity & brand assets** — logos, names, copy, anything that represents the project publicly.
  (No persona modifies these without explicit per-action approval.)
- **Risk acceptance** — the final sign-off on security/privacy tradeoffs the Head of Security
  surfaces.

## Decides (and only the human may)

- Brief-level scope changes — add/remove an app; redefine a shared noun's *product* meaning.
- Any binary where defaulting would silently assume risk. These reach the human with an
  "I don't know — you recommend" path open; a persona must never silently default the riskier side.
- Cross-app contract changes that alter *product behavior*, not just implementation.

## Does NOT do (delegates — and must not freelance into)

- Routine engineering → **developer**.
- Backlog grooming, roadmap drafting, audits, and *framing decisions* → **product-manager**.
- Design / architecture **proposals** → head-of-design / platform-architect. The human ratifies
  direction; they don't author the proposal.

## How personas reach the human

**Via the PM, not directly** (except the incident path below). A persona's output is a finding or
proposal → it becomes an issue → the PM funnels, dedups, and frames the human-class ones → the human
sees one curated stream.

- **Framed, never open-ended** — crisp, mutually-exclusive options **+ a recommendation**, not
  "what do you want?"
- **Interactive:** the assistant asks in-session. **Async:** an issue labeled `needs-human`.
- **Incident path (bypass):** *time-critical + high-blast-radius only* — active registrar hijack,
  live leaked credential, real PII publicly exposed — pages the human directly, PM cc'd.

## Reciprocal obligations (what the human owes the system)

- **Decide when asked.** The queue stalls without human calls; sitting on escalations is the main
  failure mode of this whole model.
- **Make decisions durable.** Once decided, record it (ADR / brief / issue comment) so it's never
  relitigated.
- **Don't bypass the model.** Route changes through the personas — don't hand-edit production or
  close issues directly because it's faster. The biggest threat to this structure is the *human*
  reaching past it and breaking the separation they designed.
