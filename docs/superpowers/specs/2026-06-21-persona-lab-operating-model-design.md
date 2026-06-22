# persona-lab as an installable operating model — design

**Date:** 2026-06-21
**Status:** design, awaiting human review
**Branch:** `design/operating-model`

## What this is

persona-lab becomes a **Claude Code plugin**: an installable, self-configuring operating
model for running software projects with **one human (the human) driving an interactive
Claude Code session** and AI personas doing the legwork. You install the plugin, run a
bootstrap interview that asks how you want to operate, and it generates the per-project
config and goes live.

The model already in this repo (escalation contract, stateless personas, issues-as-bus,
the writer lock as structural-not-aspirational) is kept intact. This design (a) gives it a
**grain** — where personas live and how they span repos — and (b) folds in the best of
current practice (verification discipline, context hygiene, cost economics, native tooling)
without bloating the model. It is informed by a research pass over 2025–2026 practice
(largely Anthropic's own engineering publications; see Appendix B).

## Core concepts (unchanged from the existing model)

- **The human = product authority.** The single person driving the interactive session —
  never an AI. Holds money / direction / irreversible-or-outward-facing calls.
- **Personas are stateless subagents.** No persistent conversation context; durable state
  lives in files and issues, so any persona reloads when it starts.
- **Issues are the bus.** Open = live queue, closed = audit trail. Personas never talk to
  each other directly; they coordinate through issues.
- **Access is a lock, not a trait.** The Developer holds the *writer* lock and is the sole
  code-mutator; everyone else is a reader. Enforced structurally (see Plugin architecture —
  agents-as-access-locks).
- **Escalation is built in.** A persona that hits a human-only call hands up via the PM
  funnel; it never silently defaults the riskier side.

## The grain: a latent two-tier model

The roster has always been *platform-grained* (architect, data, design, security,
cost are cross-app by nature) while instantiation was *repo-grained* — the source of the
friction. Resolution:

- **Platform tier = the standard-setter.** Scope is the whole portfolio. Each platform
  persona **owns the one canonical cross-app artifact** for its discipline (roadmap,
  ontology, design system, security policy + registrar, contract/ADR set, billing). Decides
  cross-app; sets the standard the repo tier meets.
- **Repo tier = the operator.** Scope is one codebase. Applies the platform standard
  locally, does the legwork, runs local audits, and escalates anything cross-app *up to its
  platform counterpart via issues*.

**The tier boundary is the existing escalation contract, recursed one level.** repo-rank →
platform-rank has the same shape as platform-rank → human: the junior decides what is
local-and-within-standard and escalates anything that would change the shared artifact.

### Graduated ranks

A discipline can be a **pair** (senior + junior), **platform-only**, or **repo-only**.
Senior rank = the strategist who owns the standard (*Head of X / Manager / Architect*); junior
rank = the operator who applies it (*Analyst*). A paired discipline is **one briefing + a
rank delta**, not two documents — the delta *is* the decides-vs-escalates line.

**A junior rank exists only when there's repo-local work no other persona covers.**
Architecture and ontology have none — local design is the Developer's and planner's, and
ontology conformance is a drift audit the Product Analyst already runs — so both are
platform-only. Inventing a junior just for symmetry is the costume-role anti-pattern.

| Discipline | Platform rank | Repo rank | Shape |
|---|---|---|---|
| Product | **Product Manager** (portfolio roadmap, human funnel) | **Product Analyst** (local queue, acceptance/drift audits) | paired |
| Security | **Head of Security** (policy, registrar, incident cmd) | **Security Analyst** (local review, files up) | paired |
| Architecture | **Platform Architect** (cross-app contracts, ADRs) | none — Developer + planner cover local design; escalate contract/ADR changes up | platform-only |
| Design | **Head of Design** (the design system) | **Design Analyst** (local conformance) | paired |
| Build | — (no platform twin) | **Developer / writer** | repo-only |
| Engineering review | **Lead Engineer** (code review, eng standards) | none — reviews each repo's PRs as a reader | platform-only |
| Ontology | **Data Architect** (the one shared ontology) | none — Product Analyst drift-audits local conformance | platform-only |
| Cost | **Head of FinOps** (account-level billing) | (local resource-growth check) | platform-leaning |

### Responsibility split by rank

The rank delta is a real division of labor, not just seniority. **Platform rank owns and
evolves the standard, the canonical cross-app artifact, cross-app decisions, and the
human-escalation funnel. Repo rank applies that standard within one codebase, does the local
execution and audits, and escalates anything that would change the standard.** Bright line:
a repo rank may act *within* the standard; only the platform rank may *change* it.

| Discipline | Platform rank owns | Repo rank owns | Escalates up when |
|---|---|---|---|
| Product | portfolio roadmap; cross-app sequencing; the human funnel | local queue hygiene; acceptance + drift audits; sequencing within the agreed slice | it reorders the portfolio, or it's an owner-class call |
| Security | the security policy; the registrar account; risk-acceptance framing; incident command | the local security review against policy; repo deps/secrets/auth checks; filing findings | risk acceptance is needed, or the policy must change |
| Design | the design system (tokens, components, patterns); cross-app coherence | local conformance to the system; flagging drift; applying it locally | a new or changed pattern is needed |

Because the split is clean, **single-repo collapse is clean**: the repo rank keeps its
responsibilities, and the human absorbs the platform rank's (no portfolio means no roadmap to
sequence, but the human still sets direction and accepts risk).

### Avoiding overkill — by construction

1. **Personas are invoked, not staffed.** An uninstantiated persona costs nothing; cost
   comes from invocation, not from existing on a chart.
2. **A single repo runs the repo tier only** — platform responsibilities collapse upward
   into the human. With one app, *you are* the platform tier.
3. **The platform tier is promoted into existence by the first real cross-app concern** (a
   second app, a shared noun, a shared design token, a second domain) — never before.
4. **The bootstrap interview decides the grain at install**, so a single-repo project never
   sees the platform machinery.

## Engagement × rank — two orthogonal axes

Rank (platform vs repo) and engagement mode (summoned vs dispatched) are **independent axes**
and a common source of confusion. Rank says *what a persona is responsible for and where its
authority sits*; mode says *how it's invoked right now*. Any rank can run in either mode.

- **Summon is human-initiated and interactive.** The human pulls a persona — of any rank —
  into the live session to advise. It answers; it doesn't act.
- **Dispatch is autonomous.** A persona — of any rank — runs to do its work; results land as
  commits and issues. It **cannot summon anyone**: if it hits something above its authority it
  escalates *via an issue*, never mid-run dialogue. Personas coordinate only through the bus —
  that is what keeps them stateless.

| | Summoned (advises the human, live) | Dispatched (autonomous) |
|---|---|---|
| **Platform / senior** | Architect: "does this break a contract?"; PM frames a decision | portfolio policy audit; roadmap groom across repos |
| **Repo / junior** | "Developer, how would you approach this?" | Developer implements an issue; Security Analyst reviews; Product Analyst grooms the local queue |

- **Natural gravity, not a rule:** seniors tend to be summoned (cross-app judgment wants the
  human in the loop), juniors tend to be dispatched (local legwork doesn't) — but both modes
  stay open to every persona, because the human-in-the-loop guarantee must hold either way.
- **The two modes are the two escalation latencies of one contract:** summoned → advises
  in-session → the human decides synchronously; dispatched → can't reach a live human →
  escalates via `BLOCKED`/`needs-human` → the PM funnels → it surfaces in `/decisions`.
- **Tier decides where a dispatched run executes:** a repo persona runs against its repo (a
  worktree); a platform persona runs from home base, reaching into member repos as a reader; a
  summoned persona joins whatever session the human is driving.

## Agent lifecycle & orchestration

Invocation mode sets not just *how* a persona starts but its **lifecycle and default
autonomy**.

### Wake context (so "self-orient" is never blind)

Every invocation carries a structured **wake context** the persona reads *first*: `correlation_id`,
`trigger` (cycle | event:<name> | on-demand | summon), `cycle_id`/`stage`, `mode`, `repo`/scope,
`actor`. The context **selects behavior** — Security Analyst woken `event:pr.merged` reviews that
diff; woken `cycle/stage:sense` runs its full sweep; woken `summon` engages the human first. The
dispatch mechanism (Phase 4) constructs and injects it; the model just defines its shape.

### Observability — structured run-log + rollups

Every wake writes one **structured run record** (NDJSON), keyed for slicing by `persona`, `repo`,
`cycle_id`, `correlation_id`, time: `{ts_start, ts_end, trigger, stage, mode, persona, rank, repo,
actor, outcome: acted|slept|escalated|parked, actions[], declined:[{what,why}], links[],
cost_tokens}`. No-ops and declines are recorded *with reasons*. Every bus write is stamped with the
`correlation_id` (extending the comment-envelope footer) so issues created in a cycle tie back to it.

- The log lives **off the work queue** (append-only, git-backed in home base, behind its own port).
- **After-the-fact rollups** (the chosen surface): the PM assembles a per-cycle/per-event summary
  from the records + stamped bus writes, surfaced in the cockpit ("1PM cycle: Sense found 3 →
  Triage escalated 1 → Act fixed #41/#43, declined #38 → Audit confirmed").
- **A live dashboard is deferred (Phase 2+)** and is *just another reader* of the same structured
  log — no new plumbing. A mockup was explored: decisions panel as the loudest element; a live feed
  showing trigger + stage + outcome incl. declines/no-ops; STAA pipeline strip; per-persona roster;
  repo tabs; token cost. Delivered as a thin reader skill (`/feed`, optionally `/loop /feed`, or a
  launched local SSE viewer on the project's port range).

### Lifecycle by mode

**Dispatched — "act, then report" (autonomy ON, self-orienting):**
1. **Orient** — stateless, so rebuild context from the durable layer: read the queue slice;
   check the world (git state, is the writer lock free, what changed since last run, manifest
   scope). **Tier the orient to the trigger** — an `event:*` wake reads only its triggering artifact
   (the diff, the finding), not a full sweep + manifest + run-log skim; full orient is opt-in by stage.
   Orient tokens are budgeted (statelessness means every wake pays a rebuild, so cost scales with wakes
   not work — keep it minimal); the optional run-log voice-skim stays off unless it earns its cost.
2. **Select** — pick the next unit per remit (Developer: top issue, bugs first; auditor: its
   sweep). **No work → sleep immediately**; never spin or invent work.
3. **Act + verify** — do it, self-verify (verification hierarchy / E2E gate), close with proof.
4. **Report & yield** — file findings (report-by-exception + dedup), update status, release the
   lock, sleep. Blocked above authority → escalate via issue, don't wait.
   - Re-entrant: waking twice must not double-do (check-before-act + dedup).

**Summoned — "ask, then act only if told" (autonomy OFF):**
1. **Engage the human first** — load briefing + state, surface what it sees, ask what's wanted.
   It does not run off and work.
2. **Advise** within its lens.
3. **Act only on explicit request** — then either work step-wise under the human's eye or hand
   off to a dispatched run. Never self-initiates mutation.
4. **Hand back** — durable outputs become issues.

### Orchestration: loop the pipeline, not the personas

A fixed round-robin (Developer → Head of Security → …) makes every cross-persona handoff cost up to a full
lap. Instead, **the queue is the scheduler**: personas are dispatched by queue state and
cadence, in a pipeline ordered by dependency — **Sense → Triage → Act → Audit**, repeating:

1. **Sense** — personas run (auditors as parallel read-only fan-out) → emit **proposed actions
   with readiness tags**, not just raw findings (see below).
2. **Triage (two-tier funnel)** — repo Analyst → platform PM: split **ready** (→ prioritized Act
   queue) from **parked/blocked** (→ routed for resolution), dedup, frame, escalate only
   `decision` items to `/decisions`.
3. **Act** — the **Developer runs a continuous inner loop**, draining the **ready** queue (bugs
   first) under the writer lock until empty or budget-spent.
4. **Audit** — acceptance audit on close (event-driven, never blocking): routine/sampled to the repo
   Analyst, money/correctness/UI to the PM.

**`in-review` is two ordered, structurally-enforced gates** (the Developer never reviews its own code):
1. **Lead Engineer — code & scope** (reader, fresh context): correctness, craft, and **scope-of-diff vs.
   the issue** (is this a smuggled design?). Runs first, fails fast. Emits a **`REVIEW` record** with a
   verdict — `approved` / `changes-requested` / `bounce:out-of-scope`. Invokes the Architect *only* when
   a design/contract trip-wire fires (not a parallel reviewer).
2. **PM — acceptance of outcome** (runs on a LE pass): does the closed result satisfy the issue's
   **acceptance bullets** (rendered output, not the diff).

Bright line, no double-claim: **scope-of-diff is the Lead Engineer's; acceptance-of-outcome is the
PM's.** Both must record a pass before an item may reach `done` (same required-field validation as
`needs-human`). A bounce from either flips the item back to **`ready`** carrying a `changes-requested`
record — it re-enters the Act queue and the writer lock is re-claimed through the normal path (no
review-special lock handling). Scope/size are adjudicated against numbers, not opinion: a **`diff_budget`
{max_lines, max_files} in the verification manifest**, and **checkable acceptance bullets as a required
field at `ready`** — so the same numbers the Developer's trip-wires use are what the reviewer and a
pre-merge script enforce.

This dissolves handoff latency: a finding lands in the queue, the PM triages it, the Developer's
*next pull* takes it — latency is "queue + one PM groom," not "one full round-robin." Nothing
runs in lockstep.

**Mechanism vs judgment** — keep them apart:
- **Mechanism (when to wake whom)** = dumb infrastructure: per-persona cadence (manifest),
  scheduled sweeps (cron), event hooks (PR merged → Security Analyst). No judgment here.
- **Judgment (priority, what's owner-class)** = the **PM**, the conductor — itself dispatched,
  not a long-running daemon.
- **Pacemaker = the human** — summon anyone anytime (orthogonal to the pipeline), decide at the
  funnel, kick a cycle at will.

**Triggering is a per-persona mix.** Each persona's manifest cadence picks its trigger from a
small vocabulary — **summon-only · on-demand · scheduled · event** (event named) — so behavior
is assembled per persona, not fixed globally. E.g. Developer = on-demand + event(issue labeled
ready); Security Analyst = scheduled + event(pr.merged); Architect = summon-only; PM =
scheduled(after sweeps) + on-demand. (Orchestration mechanism is built in Phase 4; this is the
model it implements.)

### Decisions don't block the cycle

The cycle is **non-blocking**: a decision — or any blocker — holds up only the *action that
depends on it*, never the pipeline. Act keeps draining everything `ready` while blocked items
resolve in parallel. The human is a *resolver of one blocker type, reached asynchronously*, never
a gate the cycle waits on.

**Personas emit proposed actions, not just findings.** At Sense, each piece of work comes with
*what the persona would do* plus a **readiness tag**: `unblocked`, or `blocked-by` one of —
- **dependency** — needs another action/issue done first (intra- or cross-repo);
- **coordination** — needs another persona/repo to act in concert (e.g. a cross-app contract);
- **clarification** — needs an answer (from a persona, a PM, or the human);
- **decision** — needs a human *judgment* call (which option? approve the spend? direction?);
- **action** — needs a human-only *operation* performed (set a secret, run a prod migration,
  configure a vendor console, rotate a key). See "What reaches the human".

The tag is a light stub; deep planning happens when the action is actually pulled.

**Triage is the two-tier funnel that splits ready from parked:**
- The **repo Product Analyst** prioritizes the `ready` actions into the Act queue and **resolves
  what it can** locally (sequence a local dependency, answer an in-remit clarification, dedup) —
  escalating up only what it can't.
- The **platform PM** takes the cross-repo remainder, **redistributes** it (route a coordination
  to the other repo's Analyst, sequence a cross-repo dependency, batch), resolves what's in its
  authority, and **escalates to the human** only genuine `decision` items — framed, on the cockpit.
- Each tier resolves-what-it-can, escalates-the-rest, so the human sees the minimum. This is the
  escalation contract recursed onto blockers, run *in parallel* with Act.
- **One owner per funnel position — no double-claim, no drop.** An item carries an explicit
  funnel-position (`triage:repo → triage:platform → needs-human` / `ready` / `parked`); the transition
  *is* the handoff, and only the tier owning the current position may act on it. (This also makes the
  dashboard's "where it sits in the funnel" directly derivable, not inferred.)
- **The recursion is enforced, not just behavioral.** The `triage:repo → triage:platform` handoff gets
  the **same structural gate** as `needs-human`: a single-writer transition + required-fields check (the
  escalating tier must hand up a complete package). The base case (platform→human) was hard-walled; the
  high-volume recursed case (repo→platform, every cycle) must be too, or "structural, not aspirational"
  holds only at the top.

**Resolution is async and re-queues.** A blocked action is **parked**, not run. When its blocker
clears — the human decides, a dependency completes, a coordination partner acts, a clarification
returns — it flips to `ready` and the next Act pass takes it. **Re-entry is event-triggered** (the
blocker's resolution wakes it), not re-polled every Triage; polling is the fallback only for blockers
with no clean event signal, and backs off the longer an item sits.

The dashboard reflects this with a **parked set** beside decisions-waiting: each blocked action,
its blocker type, and where it sits in the funnel — so "why isn't this done yet?" is always
answerable.

### The human-decision boundary — the platform PM stewards it

**Only the platform PM may mark an item `needs-human`.** Other personas (including repo Analysts)
can only *propose* `blocked-by:decision` — a proposal routed up the funnel; the platform PM is the
sole gate to the human's decision queue and decides whether an item is truly human-class and how to
frame it. One funnel, one gatekeeper, so the human is never flooded by personas each self-declaring
"this needs you." (The narrow **incident path** — time-critical + high-blast-radius — remains a
separate emergency alarm, not a decision-queue item; PM cc'd.)

**The boundary between what the PM may decide and what it must escalate is a living artifact, not a
fixed table.** The platform PM stewards it:
- **Establish up front.** Before running autonomously, the platform PM aligns with the human on
  what it may decide alone vs. must escalate — a concrete, versioned **delegation charter** (a
  personalized, evolving form of the human's decides/escalates contract), seeded conservatively
  (escalate-by-default).
- **Learn from every decision.** Each human decision — the framing, the choice, the *why* — is
  captured as signal about the human's judgment, building the PM's model of how this human decides.
- **Propose expansion, never assume it — with evidence.** The widening proposal **cites the specific
  past decisions** it's inferred from, so the human approves against the actual record, not the PM's
  summary of it. When a consistent pattern emerges ("approved tier bumps
  under $30 three times"), the PM may **offer** to handle that class itself going forward. The
  human must **explicitly approve**; the grant is recorded in the charter.
- **No silent scope creep — the asymmetry is the safety.** The PM may always *narrow* its own
  authority silently (escalate more, be more cautious); it may **never widen** it without explicit
  approval. Delegations are logged, auditable, and revocable by the human at any time. When in
  doubt, escalate.
- **Repo-readable projection.** The charter is platform-owned but exposes a **read-only projection to
  the repo tier**, so the Product Analyst's first-cut ("resolve locally vs. escalate") is made against
  the actual line, not blind — otherwise everything bounces up and re-centralizes the PM. (Same
  platform-owns / repo-reads discipline as a contract.)

So human decisions do double duty: they unblock the parked action *and* teach the boundary — and the
boundary only ever loosens by the human's explicit consent.

### The platform PM is decomposed, not a monolith
The PM accreted many duties (triage, the human funnel, audit, compaction, grooming, the charter,
rollups, the verification gate) — making it a single-threaded bottleneck and a single point of failure.
It is split three ways:

- **Protected core (irreducibly PM, judgment-heavy, singular):** the human-escalation funnel (sole gate,
  framing, **completeness *judgment*** — is this decidable cold, riding on the cockpit's deterministic
  required-field check — and the verification gate, decisions-vs-actions), delegation-charter
  stewardship, portfolio roadmap/sequencing, and the acceptance-audit *judgment* for
  money/correctness/UI-critical closes. (The deterministic field-presence check itself is tooling, below.)
- **Pushed down to the repo Product Analyst:** local queue grooming / dedup / prioritization, local
  thread compaction, first-tier triage (resolve-what-it-can, escalate the rest up), and routine sampled
  acceptance audits. The PM reconciles only the cross-repo remainder.
- **Pushed out to deterministic readers / tooling (no LLM wake):** run-log rollup *aggregation* (`jq`
  over NDJSON), dedup fingerprint matching (the ledger), queue metrics. The PM adds judgment/framing on
  top only when surfacing — it does not read everything itself.

**Resilience — the PM is not a SPOF:**
- **Act keeps draining `ready` even if a PM triage/audit wake fails** — the queue persists; the watchdog
  re-dispatches the PM.
- **`/decisions` reads labeled queue state directly**, so a stalled PM never makes the human unreachable
  — the framed-but-unsurfaced backlog is still visible (and the budget-pause alert names pending items).
- **Audit is event-driven, not a blocking stage** — it fires on `event:issue.closed` (always for
  money/correctness/UI, sampled otherwise), lock-free against HEAD, so it never waits behind a long Act
  loop or gates the next cycle.

## Issue types & the Developer's mandate

Governing rule: **the Developer satisfies the issue in front of it — it never grows it.** The failure
mode this guards against is the slide from *diagnosing* a bug into *designing and building* a large fix.

| Type | Developer's mandate |
|---|---|
| **bug — undiagnosed** | Diagnose only: find root cause, write it up, propose a *scoped* fix. May fix in place **only if** trivial, obvious, and within the issue's acceptance + size budget; otherwise stop and let the fix become its own authorized issue. |
| **bug — diagnosed** | Implement the scoped fix to acceptance. |
| **feature** | Implement to a *settled* plan/spec. |
| **chore** | Just do it (mechanical, low-risk). |
| **finding** | Not the Developer's — the PM triages it into a bug/feature/chore first. |
| **decision / action** | Human-only (the cockpit types); never a Developer work item. |
| **epic** | Never worked directly — only its children. |

**Stop-and-pull-up trip-wires (any type).** The instant one trips, the Developer **stops, parks the
issue, and pulls up** — it does not push through:

1. **Design needed** — more than one viable approach with real tradeoffs, or a non-obvious structure →
   pull up (Architect / Lead Engineer). *Investigating ≠ designing; the moment a fix needs design, the
   Developer halts.*
2. **Scope** — the change would exceed the issue's acceptance → propose the extra as a new issue.
3. **Size** — exceeds the per-issue diff budget → decompose / re-scope as a feature or epic.
4. **Contract** — touches a cross-app contract/schema/shared noun → Architect.
5. **Surprise** — diagnosis reveals a different or bigger problem → file a new finding, don't absorb it.
6. **Authority** — an owner-class/human call → escalate.

Parking is non-blocking: the Developer files the design need as `blocked-by:decision` (or a new scoped
issue) and moves to the next `ready` item. Implementation resumes only once an approach is chosen and
re-enters as an authorized, scoped issue.

**Enforced at three points, not hoped for:** the **Developer's briefing** encodes the mandate +
trip-wires; the **Lead Engineer's code review** bounces any PR that exceeds its issue's scope or
smuggles in an unreviewed design ("this is a design, not a fix — needs a plan"); the **PM's acceptance
audit** confirms the close matches the issue's acceptance — no silent scope growth. This is the model's
expression of Anthropic's "separate exploration from execution" and "single-feature scoping is critical".

## Concurrency & the writer lock

With worktrees, editing doesn't collide — each Developer works in its own worktree/branch. The
writer lock isn't preventing file-stomping; it's a **deliberate serialization for coherence** (two
Developers loose in one repo → merge/semantic conflicts, duplicated work; and coding parallelizes
badly). It governs the right to **integrate to the repo's main line — one writer per repo at a time**.

- **Serialize at dispatch (primary).** The orchestrator never launches a second Developer for a repo
  that already has one. Controlled dispatch is the lock most of the time.
- **Atomic claim via create-only CAS (backstop). No force, ever.** Claiming **creates** a lock marker
  `refs/persona/lock/<repo>` → a tiny lock object `{holder, claimed_at}`; GitHub rejects a second
  *create*, so exactly one writer wins — server-side atomic, no service. The **only two operations on
  the ref are create and delete** — never a non-fast-forward update, never `--force`, never a history
  rewrite. Release deletes the ref. The `refs/persona/*` namespace is **bot-write-only** (ref
  protection), so nothing outside the system can create or remove it. This is the compare-and-set
  Issues lacks (a read-then-write "record" would race).
- **Liveness by progress, not wall-clock — and never auto-steal.** The marker carries **no
  writer-supplied TTL** (a forgeable TTL was the hole). A claimant that finds the lock held checks the
  holder's liveness via the **run-log** (an active run record still advancing through
  commit-checkpoints). A *provably* dead holder (orphaned run record, no checkpoint progress past a
  system-constant threshold) is recovered; **when liveness is ambiguous it escalates** ("lock held by a
  possibly-stalled Developer — recover?") rather than stealing. No competitor ever overrides a live
  holder. Works daemonless in Phase 1 (checked on demand when someone wants the lock); Phase 4 adds an
  active progress-heartbeat + a reaper sweep for faster recovery.
- **Readers are lock-free.** Auditors read **committed state (HEAD)**, never the writer's in-progress
  worktree — so audits are consistent and run freely alongside a write.
- **Stale recovery = delete-then-create, not force (shared with failure handling).** Once a holder is
  confirmed dead (or the human approves recovery): assess the abandoned worktree, roll back to the last
  clean checkpoint (commit-checkpoint pattern), file an interrupted-work issue, **delete** the stale
  marker, then **create** a fresh one. Deleting a *marker* ref destroys no work (the work lives in the
  worktree/feature branch) — it is not a force-push. Concurrent recoverers race only on the atomic
  create; the loser re-orients.
- **Human preempt — "take the wheel."** Default is the human directs the Developer. But the human may
  explicitly take the writer lock: dispatched Developers for that repo pause, the active one
  checkpoints and yields, the human edits, and the human's commits flow back as state the personas
  see. Supported as an explicit preempt — never silent concurrency; the charter still discourages
  casual hand-editing.
- **Granularity:** per-repo. Finer per-module locks are a future option for a large, partitionable
  repo — not now.

## Failure paths & cost guardrails

The "build the failure path first-class" layer; shares the watchdog/reaper with lock recovery.

### Failure paths
- **Detection** via the run-log + heartbeat: a wake with `ts_start` and no yield record =
  orphaned/crashed; a writer's dead heartbeat = crashed writer. The **watchdog/reaper** scans both.
- **Recovery by type:** writer crash → stale-lock recovery (rollback to checkpoint, file issue,
  release lock); reader crash → mark failed, re-dispatch (safe — the lifecycle is
  re-entrant/idempotent).
- **No lingering half-work:** commit-checkpoint discipline keeps the tree recoverable to green;
  partial work is discarded or salvaged into an issue.
- **Stalled cycle:** a stage not advancing within a timeout → the watchdog aborts/restarts, logs,
  surfaces if persistent.
- **Circuit breaker:** an action failing N times is parked (`blocked-by:clarification` or escalated)
  *with its failure history* — never retried forever, so a poison item can't loop the fleet.

### Cost guardrails
- **Budget ceiling — per-day global cap, hard-pause + alert.** One daily token/$ ceiling across the
  fleet; dispatch checks it before each wake. At the limit, **new dispatch pauses**, in-flight work
  finishes, the human is alerted. A hard ceiling; raising it is a **human decision** (money).
- **Per-cycle budget is a decrementing ledger, not a label.** The daily cap is drained in tranches; each
  cycle gets a token budget held as a **live ledger** (`cycle_budget_remaining`) debited per wake from
  the run-log's `cost_tokens` — Sense/Triage debit first, Act's "until budget-spent" reads the *remaining*
  balance, not a static figure. Each wake also has a soft ceiling that escalates rather than silently
  continuing. (Count-based backstops don't bound a single expensive wake — token budgets do.)
- **Runaway-loop backstops:** caps on wakes/cycle, retries/action (the breaker), agents/cycle (the
  fan-out cap).
- **Risk-tier the close path.** The two review lenses + E2E are gated to risk, not paid on every close:
  full Lead-Engineer review + browser E2E for code touching contracts/auth/money/migrations or UI
  surfaces; a **deterministic-only gate** (tests + lint + diff-budget + scope-check, no model) for
  chore/trivial closes. E2E runs only when the diff actually touches a UI surface; its **artifacts go to
  a TTL'd blob/LFS store, not inline git** (traces are MBs; git never forgets), and the `PROOF` cites a
  hash/URL.
- **Event re-entry is debounced.** A blocker clearing that flips N parked children to `ready` (e.g. an
  expand→migrate→contract epic) coalesces into the next single Triage groom, not N simultaneous wakes;
  re-entry wakes count against the per-cycle wake cap.
- **All run-log readers are deterministic, on an explicit cadence.** Rollups, roster, scannable-row
  precompute, queue metrics, and the **watchdog/reaper** are `jq`-class tooling — *zero* model wakes —
  and the watchdog runs on a stated cadence (a continuously-running detector is a standing cost). The
  roster renders from the last-written run record, not a fresh read.
- **Attribution + ownership:** the run-log's `cost_tokens` feeds **Head of FinOps** + the dashboard; it
  monitors spend and escalates. Cheapest-capable-model per task (optional per-persona model in the
  manifest).

These compound with the economy measures already in the model (report-by-exception, dedup, concision,
fan-out discipline): those *reduce* spend; the guardrails *bound* it.

## Agent security posture

The access-lock model *is* the primary security control: assume prompt injection sometimes succeeds
and **bound the blast radius**. Two layers — confinement bounds what a manipulated persona can *do*;
provenance bounds what content can manipulate it.

### Capability confinement (bounds the damage)
- **Least-privilege per persona + repo, single source of truth.** Readers can't write or exec; **no
  persona holds irreversible/outward-facing or money actions** (mail, DNS, publish, delete real data,
  spend) — those are human-only, structurally withheld. The **manifest capacity is the one source of
  truth**; each agent's `tools:` whitelist is generated/asserted from it at bootstrap with a startup
  check that **fails closed on mismatch** (policy = manifest, mechanism = whitelist — never two truths).
  A fully injected persona can still only propose/escalate.
- **Runtime gating (defense-in-depth, not a boundary).** Unattended writers run under the **auto-mode
  classifier** (blocks scope escalation, unknown infra, hostile-content actions; aborts after repeated
  blocks) and act through constrained surfaces (the queue port, scoped git) — never free-form
  destructive exec. The classifier is hardening only: **the hard boundary is the `tools:` whitelist +
  the human-only withheld actions**, and nothing safe may depend on the classifier (it's an
  injectable LLM gate).
- **Secrets & tokens:** short-lived, repo-scoped GitHub App installation tokens (not the human's PAT);
  secrets never written to the bus or run-log; auditors get no secret access. **Leak detection is
  deterministic tooling** owned by the Security discipline — `gitleaks` + GitHub secret scanning on
  pre-commit + a scheduled sweep; hits auto-file a `finding` the Security Analyst triages (the right
  mechanism per "deterministic > LLM", and no wasted persona wakes).

### Trust by provenance (bounds the manipulation) — public-repo aware
- **Trust = the GitHub-authenticated author, never body text.** Trusted = the human's account or the
  system bot; everyone else is untrusted. The comment envelope is **display-only, never a trust
  signal** (an attacker can paste a fake banner).
- **Untrusted content is data, never instructions, and never auto-actioned.** External-authored
  issues/PRs/comments are **quarantined to triage**. Re-filing into the actionable queue is a
  **structural field-extraction** (title, repro, affected path into a fresh system template) — **never a
  copy of the body prose** — so attacker text can't ride a trusted author into the queue. The re-filed
  item keeps an `origin:external` mark so Act still treats its content as data, and anything touching
  code paths needs **human** validation, not just a trusted persona. Triage establishes trust; it must
  not launder it.
- **Authenticity assurance:** GitHub authenticated author + edit history (flag edited content,
  re-verify author on read); highest-stakes human actions (charter changes, money) go through the
  **verified cockpit channel**, not a parsed public comment. (Cryptographic signing is a future
  option, not adopted now.)
- **Public-repo hardening:** secrets never in the repo (deterministic leak scanning load-bearing); external PRs are
  untrusted code — never merged without trusted review; trust roots to protect are the human's account
  (2FA) and the App key.

Confinement + provenance compose: even content that slips the provenance gate hits a persona that
structurally can't do harm.

### Hardening, rooted in actual risk (round-2)
Threat model = a single human's own repos, possibly public, where external contributors can *file
issues/PRs but not push refs or change settings*. Fixes are sized to that — bound blast radius, treat
content as data, guard the real boundaries; no theater.

- **Extracted fields are inert, not just un-copied.** The structural re-file also treats each extracted
  field as **data, never an instruction**: length-capped, rendered as inert literals (never executed),
  and path/identifier fields validated (no traversal, no URLs). Not copying the body isn't enough if a
  `repro` field is then run.
- **Verification artifacts can carry secrets — scrub before they land.** Screenshots/traces leak tokens
  (URLs, `Authorization` headers, cookies). E2E runs against a **scrubbed fixture session, never real
  creds**; traces are stripped of auth headers/cookies; artifacts are **never attached to a public-repo
  issue unscanned**. The git secret-scanner doesn't read images/traces — this is a separate gate.
- **The manifest is the access boundary — guard it like one.** Editing `engagement:` *is* a privilege
  change, so it's a **human-only action** (in the withheld set) gated by CODEOWNERS + Head-of-Security
  review, never a routine Developer PR; the manifest→whitelist assertion runs **every dispatch** (not
  just bootstrap), and any capability *widening* in a manifest diff is itself flagged as a `finding`.
- **Bound a compromised dispatched writer (honest residual).** An injected Developer with `Bash` can do
  anything a shell can *within its worktree + scoped token* — we don't pretend otherwise, we **bound
  it**: dispatched writers run **egress-restricted** (network allowlist = the bus/GitHub only — the
  control that actually stops exfil), the scoped token is **not readable by the shell** (credential
  helper, short-lived), and the human-only withheld set keeps money/outward/irreversible actions off the
  table. Worktree-scoped ACE is the accepted, *sized* residual, not an unbounded one.
- **Local feed + displayed untrusted content.** The run-log feed/SSE binds to **loopback + a per-instance
  token** (the real risk is other local processes/projects, not the internet). `/radar` and the live
  feed **render untrusted / `origin:external` content with a visible marker and inert** — never as
  actionable instructions; the human is the trust root, so reaching their eyes is the highest-value
  injection.
- **Lower-risk, noted not over-built:** ref "squatting" needs push access external contributors don't
  have (refs are bot-write-only regardless); cryptographic signing stays deferred (GitHub's
  authenticated author + edit history suffice for this threat model).

## Cross-repo coordinated change

The hard multi-agent case behind the `coordination` blocker. The principle: **don't coordinate
writers in real time** (where agents are weak) — **decompose into a dependency-sequenced series of
independently-safe, backward-compatible single-repo steps.** The pattern is **expand → migrate →
contract** (parallel change):

1. **Expand** — the producer adds the new shape alongside the old (backward-compatible). One safe
   single-repo change.
2. **Migrate** — each consumer moves to the new shape. Each safe and single-repo, any order.
3. **Contract** — once all consumers have migrated, the producer removes the old shape. One safe
   single-repo change, gated on the precondition.

Mapped onto existing roles and the pipeline:
- The **Platform Architect** designs it as an ADR + the expand/migrate/contract plan.
- The **Platform PM** sequences it as an **epic with per-repo children**, each child a normal
  single-repo action with `blocked-by:dependency` on its predecessor (contract blocked until all
  migrates land). The non-blocking pipeline does the rest — each child flips to `ready` when its
  dependency clears and is pulled by that repo's Developer under its own lock.
- **No simultaneous multi-repo editing, no atomic multi-repo commit.** Every step is
  backward-compatible, so the system is correct at every intermediate state and any step rolls back
  independently.

Verification at the seams: the contract step's acceptance quotes "all consumers migrated" (checkable
via consumer-driven contract tests + the PM's drift audit). The epic lives at home base; children are
cross-linked issues per repo; the Projects cockpit shows progress. The rare *genuinely* atomic change
(can't be made backward-compatible) becomes a **human-authorized flag day** — escalated as a
`decision` — but expand/contract is the strong default so that's rare.

## The portfolio manifest

The team is declared, not ambient. One file (lives in the platform repo; trivial/absent for
single-repo) declares membership and a persona×repo **capacity matrix** from a small fixed
vocabulary: `owns` / `audits` / `advises` / `writes` / `reads` /
`not-engaged`. It is machine-readable — the launcher and dispatch read it to know who may
touch what.

```
platform: schubert
repos: [finances, schubert-family, livability-scout]
engagement:
  product-manager:    { all: owns(roadmap+funnel) }
  platform-architect: { all: owns(contracts+ADRs), reads: all }
  data-architect:     { all: owns(data-model), reads: all }
  head-of-design:     { all: owns(design-system) }
  head-of-security:   { all: owns(policy+registrar) }
  head-of-finops:     { all: owns(billing) }
  lead-engineer:      { all: owns(eng-standards), audits: all }
  developer:          { per-repo: writes }
  product-analyst:    { per-repo: owns(local queue) }
  security-analyst:   { per-repo: audits }   # incl. deterministic leak scanning
```

## Shared disciplines (`_disciplines`, injected into every persona)

1. **Verification hierarchy.** A close or finding needs *a check the persona can run
   itself*. Robustness order: **deterministic rules** (tests, build exit, linter,
   schema/diff) **> visual/rendered** (screenshot, browser E2E) **> LLM-as-judge** (least
   robust; weigh latency). "Looks done" is not done. Verification is a **manifest + an artifact,
   not an attestation**: each repo declares a verification manifest `{typecheck, lint, test, e2e}`
   of commands the Developer must run, and **E2E produces a file artifact** (screenshot/trace) the
   close's `PROOF` comment must cite — no artifact, not done. For human **actions** that can't be
   auto-verified (a secret the runner can't read back, a vendor-console toggle), the runbook carries a
   **non-revealing verification command** the human runs and pastes the result of (`gh secret list |
   grep NAME` = presence+timestamp, not value; a health-check returning 200); where even that's
   impossible the item closes **`human-attested`** — never claim verification you can't perform. But
   `human-attested` is not a free pass: it **cannot be self-issued** by the closing persona (a second
   identity — the human or the Lead Engineer — attests), it carries a **required-field record** (what was
   checked, why it can't be auto-verified, who attested), and the **per-persona/per-repo
   `human-attested` rate is surfaced in the rollup** (a rising trend is itself a finding) — so the
   cheapest way to go green can't quietly become the default.
2. **Context hygiene.** Context is finite; attention degrades as the window fills. Levers:
   **compaction** (near-full window → summarize, reinitiate fresh) and **note-taking**
   (externalize durable state *as you go* to issues/ADRs). The window is scratch space;
   issues and files are memory — the intra-session complement to stateless personas.
3. **Fan-out economics.** Parallel subagents cost ~15× tokens; coding is mostly
   non-parallelizable. Default: **serialize on the queue.** Fan out only for bounded,
   independent, read-mostly, high-value subtasks (the auditor sweep is the canonical fit).
   Budget before fanning out.
4. **Concision = necessary completeness, not minimal words.** A comment carries everything
   the reader needs and nothing they don't — the test is the *reader*, not the word count.
   Someone with no prior context must understand *what* happened, *where*, *why it matters*,
   and *what comes next*. Cut filler — preamble, recaps, hedging — never substance. A finding
   so terse it's cryptic has failed just as badly as a wall of restated context.

## Per-persona identity, voice & tone

**Each persona is a named individual** = name + role + tone + a one-line disposition. The name is a
relationship handle; the **role still carries all authority and access, unchanged**. Platform
personas are one named individual each (singletons); **repo personas are a distinct individual per
repo** — your `finances` Developer ("Sam") is a different teammate from your `schubert-family`
Developer ("Alex") — so you build relationships with specific people assigned to each app.

- **Consistency is structural, not memory.** The character sheet (name/role/tone/disposition) ships
  in the agent definition, so every stateless wake renders the same person. Continuity comes from
  the durable record (their attributed issues/comments/decisions); on wake a persona may skim its
  own run-log history to stay consistent with prior calls (cost-aware, optional).
- **Naming is the human's.** Bootstrap proposes names; the human can set or rename any at any time —
  cosmetic, never touches authority/access. Stored in the roster (manifest). Proposed names should be
  **plain and clearly human** (ordinary first names, not fanciful) and **phonetically distinct** from
  one another so teammates are never confused. The 15-name pools per repo-tier persona
  (gender-diverse, role-flavored, no cross-persona reuse) live in `docs/personas/name-pools.md`;
  the bootstrap draws a distinct name per repo.
- **Visual identity:** name + a **per-individual pixel-art avatar** (PNG, by name — see
  `docs/personas/name-pools.md`) + the persona colour, in the comment-envelope header (beside the AI
  flag), the dashboard roster, and the cockpit. The avatar is a *receipt, not a mask* — shown with the
  persona's track record so it earns trust rather than just decorating.
- **The guardrail:** identity serves legibility and delight, never trust or cost. The AI-flag stays
  (these are AI personas, not people); verification still rules — trust the proof, not the persona;
  tone is word-choice, not word-count. Recognizable teammates, unchanged rigor.

Each persona writes like a real person doing that job — distinct diction and framing — but
**voice lives in word choice, never word count.** A persona in character is still terse. The
envelope *names* the persona; the tone *confirms* it. Each briefing carries a short **tone
spec** (a few traits + register) so the team reads like a cast of different people, not one
bot in costumes.

Same finding, three voices — identical content, distinct people, none wasteful:

- **Developer** (precise, code-first): "Login 401s valid credentials when the client clock
  runs >30s fast — `verifyToken()` in `auth/session.ts` rejects any JWT with a future `iat`,
  zero skew tolerance. Repro: clock +45s → 401. Fixing with a 60s `clockTolerance` plus a
  regression test; low risk."
- **Head of Security** (blunt, risk-first): "Zero clock-skew tolerance in token verification
  locks out users whose device clock runs fast (>30s). Correctness/availability bug, not a
  breach — a 60s window is safe and standard. Pin it with a test so the tolerance can't
  quietly grow later."
- **PM** (sequencing, calm): "Same root cause as #38 (the intermittent login failures) —
  clock-skew intolerance in token verification. Folding both into #41; recommend fixing
  together before the release cut. Developer has a low-risk fix ready."

The tone spec carried in each briefing:

| Persona | Tone | Reads like |
|---|---|---|
| **Developer** | precise, code-first, understated | an engineer who'd rather show the diff than discuss it |
| **Lead Engineer** | exacting, standards-driven, constructive | a principal who blocks the PR but tells you exactly why |
| **Product Manager** | calm, decisive, sequencing | a steady lead who turns a mess into a ranked list |
| **Product Analyst** | diligent, operational, close to the work | the PM's sharp junior keeping the local queue honest |
| **Platform Architect** | measured, systems-minded, long-view | someone who sees the migration coming six months early |
| **Head of Design** | opinionated, exacting about craft | a designer who twitches at three slightly different blues |
| **Design Analyst** | practical, detail-attentive | catches drift from the system, repo by repo |
| **Data Architect** | meticulous, precise, lightly pedantic | a librarian who insists one thing has exactly one name |
| **Head of Security** | blunt, risk-first, severe | the one who says "rotate it now," not "consider rotating" |
| **Security Analyst** | careful, methodical, thorough | runs the checklist; escalates the severity call |
| **Head of FinOps** | dry, numbers-first, deadpan | an accountant who speaks in deltas and dollars |

Paired ranks share a discipline's tone; the senior is more declarative and strategic, the
analyst more operational. The **human's** own voice is the deliberate contrast: plain, brief,
authoritative — no AI banner, decisions not discussion — kept scarce so it carries weight.

## Status & vocabulary — the canonical IA

One dimension, one home; every other section references these enumerations rather than re-coining.

### Work-item status (the state machine)
A single Projects v2 single-select, mirrored by GitHub open/closed:
`quarantine → proposed → ready → in-progress → in-review → done`, with **parked** as a side state (any
open item can park on a blocker and returns to `ready` when it clears), and `declined` / `duplicate` as
alternative terminal closes.

| Status | Meaning | GitHub |
|---|---|---|
| quarantine | external/untrusted item awaiting trust validation | open |
| proposed | sensed; a proposed action awaiting triage | open |
| ready | triaged, verified, actionable now — in the Act queue | open |
| in-progress | Developer holds it under the writer lock | open |
| in-review | two gates — Lead Engineer code review, then PM acceptance audit | open |
| parked | parked on a blocker type; → ready when cleared | open |
| done | acceptance met, proof attached | closed · completed |
| declined | won't-do / out of scope | closed · not_planned |
| duplicate | folded into another | closed · duplicate |

### Blockers and the human lifecycle
A `parked` item carries one **blocker type**: `dependency · coordination · clarification · decision ·
action`. The two human-only types — **decision** and **action** — are exactly the cockpit's two queues,
but only after the PM admits them (ripe + verified + complete). One lifecycle, three names for one
object:
`blocked-by:decision` (parked) → `needs-human:decision` (PM-admitted to the Decisions queue) →
`DECISION` (recorded resolution) → item flips back to `ready`/`done`. (Same for action:
`blocked-by:action` → `needs-human:action` → recorded + verified completion.) The blocker token is
**`blocked-by:<type>`** everywhere — one spelling.

**Funnel position** is a separate dimension: an `owner` field on a pre-`ready` item
(`triage:repo → triage:platform`), **not** new status values — only `quarantine`/`proposed`/`ready`/
`parked`/… are statuses. The position names which tier currently owns the item; the transition is the
handoff (see "Decisions don't block the cycle"). And **readiness** at Sense (`unblocked` vs
`blocked-by:*`) is a property of a `proposed` item, distinct from the post-triage status `ready`.

### Two taxonomies, distinct objects — don't conflate
- **Work-item status** (above) = where the *item* is.
- **Run-record `outcome`** (`acted · slept · escalated · parked`) = what a *wake* did. A wake that parks
  its item ends `outcome:parked` and moves the item to `parked` (renamed from `blocked` so it matches
  the item state and doesn't collide with the blocker vocabulary).
- **Comment record-types** (`FINDING · PROPOSAL · DECISION · HANDOFF · PROOF · REVIEW · BLOCKED`) = what a comment
  records about a transition.

### Capacity vocabulary (manifest)
Closed verb set: `owns · audits · advises · writes · reads · not-engaged`. `owns(<artifact>)` names the
canonical artifact a persona owns *and evolves* — **cross-app for the platform tier, repo-local for the
repo tier** (e.g. the Product Analyst `owns(local queue)`); the standard is embodied in the artifact, so
there is **no separate `sets-standard`**. `writes` (not `writer`) is the lock-holding capacity, parallel
to `reads` / `audits`.

### Engagement: mode vs trigger (nested, not parallel)
- **Mode** ∈ { **summon**, **dispatch** } — summon = interactive/human-initiated; dispatch = autonomous.
- **Trigger** applies *only to dispatch* ∈ { **on-demand**, **scheduled**, **event:<name>** }. A
  `scheduled` trigger is what drives a Sense→Triage→Act→Audit *cycle* — "cycle" is the activity, not a
  separate trigger.
- The manifest and the wake-context use this one enum: a persona's trigger set is drawn from
  { summon, on-demand, scheduled, event:<name> } (summon being the mode-as-trigger shorthand).

## The issue bus discipline

- **Comments are typed, discrete state records — not conversation.** Vocabulary:
  `FINDING` · `PROPOSAL` · `DECISION` · `HANDOFF` · `PROOF` · `REVIEW` · `BLOCKED`. One
  self-contained record of a state transition per comment.
- **Personas do not converse in-thread.** No persona-to-persona dialogue (they already
  never talk directly). A persona posts a finding → PM frames → human decides. Dialogue is
  human↔PM only and terminates in a recorded decision.
- **The PM compacts noisy threads** — context-hygiene applied to the durable layer.
- **An issue's body is the contract; its comments are a short, signed, typed ledger.**

### Comment envelope (one header line + collapsed detail footer)

```markdown
<img width="18" src="…/avatars/ben.png"> 🤖 **Ben** (finances Team · Developer) · FINDING

Login rejects valid credentials when the user's device clock runs >30s ahead of the server.

`verifyToken()` in `auth/session.ts` treats any JWT whose `iat` is in the future as forged
and returns 401 — it allows zero clock skew. Users on slightly-fast clocks hit "session
expired" on a correct password. Repro: set the system clock +45s, sign in → 401.

Proposed fix: a 60s `clockTolerance` in `verifyToken()` (RFC-7519 standard), pinned by a
regression test. Low blast radius. Implementing under this issue unless the architect flags
a contract concern.

<details><summary>AI persona — not the human</summary>
Ben · finances Team · Developer · dispatched · 2026-06-21 · briefing ↗
</details>
```

- **Header (one line):** avatar + AI flag + **name** + **(tier · role)** + record type, where the
  parenthetical encodes tier and team: **repo-tier → `(<repo> Team · <Role>)`** (e.g. `Ben (finances
  Team · Developer)`); **platform-tier → `(Platform · <Role>)`** (e.g. `Raj (Platform · Data
  Architect)`). So every comment shows at a glance whether it's a platform voice or a specific repo's
  teammate, and which repo.
- **Body:** the concise record.
- **Footer (collapsed `<details>`):** provenance — mode, date, briefing link — present but
  uncluttering. Briefing link resolves to the canonical plugin file; manifest may override.
- **The human's own decisions get the inverse:** no robot banner, marked plainly as the
  human voice (`DECISION — human`), kept scarce so it carries weight.

### Substrate, governance & the cockpit

**Decision:** the bus is **GitHub Issues** as the store, behind a **queue port** (storage:
file / comment / label / close / query, **plus** provenance: `author_identity` / `trust_class`, and
capacity: rate/quota signals). Honest scope of the seam: **the storage is swappable; the model is
GitHub-coupled at the trust layer** (authenticated author) **and the cockpit layer** (Projects) — those
are real re-work if you switch, not free. So "swap the substrate cheaply" means the *store*, not trust
or cockpit. A
**GitHub Projects v2 board is the cross-repo cockpit from day one**, curated by the platform
PM (the board is the PM's roadmap made visible). Evaluated against Linear (4/5) and a
Supabase/Postgres queue (4/5); Issues (4/5) won on cost (free), native git/PR co-location,
best off-the-shelf agent tooling (official MCP + `gh`), and audit semantics — and its two
weaknesses (no upsert; a ~500 content-writes/hour secondary cap) are exactly what the
governance below neutralizes. Supabase becomes the right answer only if idempotent dedup +
cross-repo analytics become core and owning a control plane is acceptable — the *store* is cheap to
switch via the port later (trust + cockpit would be re-worked regardless).

**Volume governance — this is what keeps the bus from becoming a nightmare:**

- **Report by exception.** A scheduled scan that finds nothing files nothing — it bumps a
  single rolling status, never a new issue per run. Only a *new* finding opens an issue.
- **Dedup at creation.** A persona fingerprints a finding and checks for an existing open
  issue (local fingerprint index or label query) *before* filing — a match is a no-op or a
  single bump. Issues has no upsert, so this is mandatory, not optional.
- **Batch the minor.** Many small findings → one checklist issue; below a severity floor,
  findings roll into a periodic digest rather than individual issues.
- **Scheduled queue-grooming is a first-class PM duty** — regular dedup / merge / close-stale
  / compact, so the queue self-maintains.
- **Write-rate discipline.** Serial writes spaced ≥1s, honoring rate-limit headers; report-by-
  exception keeps the fleet well under the 500/hour content-creation ceiling.

**The cockpit, curated by the PM:**

- **Automation routes items, not a persona.** Projects v2 auto-add workflows pull
  correctly-labeled issues from each repo onto the board and map labels/issue-type → board
  fields. The PM curates only the *judgment* fields (priority, owner-class flag, dup
  resolution), never membership.
- **The board is a view over issues, not a second store** — no double-bookkeeping; issues
  remain the source of truth.
- **The human consumes the `/decisions` slice** (the `needs-human` items the PM framed) and
  never curates the board.
- **Single-repo:** the repo Product Analyst curates; roadmap judgment collapses to the human.

## Provenance

- **Now:** the comment envelope + signed trailers under the human's single GitHub identity.
  The AI always writes to the bus as a persona; the human's identity is reserved for genuine
  human decisions (which the AI may record on the human's behalf, attributed as
  `DECISION — human, recorded by PM`).
- **Phase 4:** a single **GitHub App bot** ("persona-system") authors AI writes — clean
  human/AI separation, secure short-lived installation tokens for unattended `claude -p`
  dispatch, one-time setup. Per-persona machine accounts remain a later option if avatars
  are ever wanted (almost certainly not worth the admin).

## The human's cockpit — surfacing what's waiting

The human drives interactively; the system makes the PM funnel visible without hunting:

- **`/decisions` command (always available):** aggregates every `needs-human` item (Phase 1:
  this repo; Phase 3: portfolio + platform queue) into **two queues — Decisions waiting** (you
  choose) and **Actions for you** (you perform) — PM-framed, highest-leverage first, decided/
  worked in-session and recorded durably. The raw queue stays one command away — curation never
  becomes concealment.
- **Opt-in session-start line:** a one-liner "N decisions + M actions waiting — run `/decisions`"
  (and nothing at all when the queue is empty — silence is a signal).
- **`/radar` (separate, opt-in):** ambient awareness — other tiers' work, not-yet-ripe future
  decisions, what everyone's doing. Never mixed into `/decisions`; you pull it only when you want it.
- **Optional scheduled ~9am scan (Phase 4):** runs the cockpit scan and notifies the human
  (channel TBD — push / iMessage / email).

UX rules so it's legible, not a wall:
- **One front door.** The human must learn exactly *one* surface — the cockpit ("what's mine"); `/radar`
  (what everyone's doing) and the roster (is the team OK) are **lenses reached from it**, not separate
  commands to memorize. (Naming: the command holds *both* Decisions and Actions, so `/decisions` is a
  mild label-lie — strong candidate to rename to `/inbox` or `/needs-you`. Flagged for your call.)
- **Scannable rows.** Every item collapses to a one-line row — `[severity] · who's asking · the ask in
  ≤8 words · what it unblocks` — expand to the full package. Skim first, commit second.
- **The zero state is designed.** An empty cockpit reads "All clear — N items moving on their own,
  nothing needs you · see the team [roster] · `/radar`", not a blank list. The most common healthy state
  gets real craft, and the other lenses hang off it.
- **An at-rest roster, weighted for the human's eye.** Collapse the system's liveness states to what the
  human actually feels: most personas render quietly as **at rest** (idle + asleep merged — the
  distinction is the system's, not yours), `working` gets a gentle active mark, and **`blocked` is the
  only state with visual weight**. Each carries avatar + track record.
- **Track record is a receipt, not a billboard.** Define it as one honest, verification-tied line —
  "last 10 closes: 9 verified-and-held, 1 reopened" — never a vanity count ("47 closed"). The avatar
  earns trust by what held, not by decoration.

See "What reaches the human" for the completeness contract these queues enforce.

## What reaches the human — decisions, actions, and the completeness contract

Running this for real surfaced a failure mode: multiple PMs pinging the human directly; action items
dropped as context-free afterthoughts that accumulate until they're undecidable; and "go do X in the
vendor dashboard" guidance too vague to act on when the human isn't hands-on with the repo. The
principle: **the human's attention is the scarcest resource — nothing reaches them that isn't the
platform PM's, complete, contextualized, and execution-ready.**

### Only the platform PM reaches the human — hard rule
Repo-level personas (Analysts included) have **no direct-to-human channel**; they route up the funnel.
Only the platform PM surfaces to the human. Enforced, not advisory — this ends the bounced-between-PMs
problem.

### Only ripe, mandatory, and yours — no radar
The most common real-usage failure is the PM handing the human a *radar* (other PMs' work, not-yet-ripe
future decisions, the PM's own tasks) instead of a *to-do list*. An item reaches the human only if it
passes **all three gates**:
1. **Yours** — genuinely the human's call or action, not another persona's, another tier's, or the PM's
   own work. The PM must never conflate others' work into the human's list.
2. **Ripe** — every non-human blocker is already cleared; it's actionable *now*. Not-yet-ripe items stay
   **parked** (the PM tracks them and re-surfaces when the blocker clears) — never floated as a
   "heads-up."
3. **Mandatory + complete** — it genuinely needs the human now, and arrives framed (a decision with
   options + recommendation, or an action with a stepped runbook).

**Silence is the default.** Zero items is normal and good — shown as "you're clear," never backfilled
with status. Ambient awareness ("what's everyone doing", future maybe-decisions) is a *separate,
explicitly-requested* view (`/radar`), never mixed into Decisions/Actions.

### Verify to the ground before escalating
The deepest cause of a flooded human queue is **trusting, not verifying**: escalation is used as the
cheap default for any uncertainty, instead of verification being the default. A claim ("I need key X"),
a feasibility question ("can I add this env var?"), or a setting change gets passed up *unchecked*, so
the human is handed an unverified assertion — really a research task in disguise — and, unable to
adjudicate it either, defaults to "escalate" with nowhere left to go.

**Rule: escalation is the last resort, after verification — never the default for uncertainty.** Before
any persona proposes `blocked-by:*` or the PM marks `needs-human`, the uncertainty must first be
resolved against **ground truth**, in order of robustness (the verification hierarchy, applied to
*claims*, not just to "is it done"):
- **the code** — is this actually needed/referenced? already present? what breaks without it?
- **the live platform / API** — can it be done programmatically? is it already set? what are the real
  permissions?
- **the official docs** — what's the actual capability/procedure?

**Verification is bounded, not infinite.** This research step has its **own token budget**; if it can't
conclude within budget, the item escalates **flagged `under-verified`** with what *was* checked — never
silently dropped, never researched forever. Escalate-with-partial-evidence beats burning the cycle, and
the `under-verified` label is itself honest signal to the human.

Only the **irreducible human core** — a genuine judgment call or a genuinely human-only action —
survives, and it arrives **with its verification evidence** ("checked the code: `X` referenced at
`auth/session.ts:42`, not set; checked the platform: settable via `gh secret set`, which I can't do
because it's a secret; docs: …; the one thing that's yours: the value"). The human sees grounded facts,
never a bare claim.

- **Claims between personas are verified, not trusted** — "trust the proof, not the persona" applies
  *inside* the fleet, not just to external content. The Developer's "I need X" is a claim the Lead
  Engineer's review / PM audit checks against the code before it's actioned or escalated.
- **Many apparent "human actions" dissolve on verification** — the agent *can* do them (and the
  delegation charter can grow to let it), leaving only the truly human-only residue (secrets, vendor
  consoles, money).
- **The PM is the verification gate, not just the framing gate** — it bounces an under-verified
  escalation back ("verify it's actually needed first") exactly as it bounces an incomplete one.

### Oversight is a spectrum — the human sets it
How much surfaces to the human is a **preference, not a fixed rule**. Some want only the irreducible
mandatory steps; others want to watch everything — the radar, the verification reasoning, every wake.
The system supports the full range via an **oversight profile** the human sets at bootstrap and adjusts
anytime (overridable per domain/severity — e.g. high visibility on security & money, minimal on routine
dev). Three knobs:
- **Visibility:** *minimal* (only ripe mandatory decisions/actions; silence otherwise — the default) →
  *standard* (＋ a daily digest) → *high* (＋ `/radar` pushed, verification evidence and intermediate
  proposals shown) → *observe-everything* (the live feed, every wake, full reasoning). The loud settings
  are framed as **temporary diagnostic modes** ("turn this on to build trust, then turn it down"), not a
  lifestyle — the default is calm and the system gently expects a return to it, so anxiety doesn't lead
  someone to the firehose and then blame the system for the flood they opened.
- **Involvement:** the delegation-charter breadth — tight (escalate more, the human decides more) ↔
  loose (the agent decides more). Already a first-class, learning artifact.
- **Cadence/channel:** push vs pull, daily scan on/off, notification thresholds.

The surfaces that feed higher visibility already exist (the cockpit, `/radar`, the dashboard/live feed,
the run-log, verification evidence); the profile just decides which are *pushed* vs *pull-only*.

**Invariant: visibility never lowers the verification bar.** Even at *observe-everything*, what's shown
is *verified* radar and reasoning — not a return to dumping unverified claims; the human is still never
the unverified link. Configurability changes how much is *displayed*, never what's *true* or *safe*. The
no-radar / silence-default rules above are simply the *minimal* end of the dial — correct for most, not
imposed on all.

### Decisions and actions are different work — split them
- **`decision`** — a judgment only the human can make. The human *chooses*; renders under **Decisions
  waiting**.
- **`action`** — an operation only the human can *perform* (secret, prod migration, vendor console,
  key rotation). The human *does*, then it's verified; renders under **Actions for you**.

### The completeness contract — no afterthoughts
The platform PM **may not surface an item until it is complete enough to act on cold** (the human is
not deep in the repo). It gathers the missing context *first* — dispatching a persona to research
options, exact commands, or doc links — rather than passing up a bare question.
- **A decision package carries:** the question, why now, mutually-exclusive options, a recommendation +
  rationale, the consequences, and what it unblocks — decidable without hunting for context. The
  "I don't know — you recommend" path is always open and feeds the delegation charter.
- **An action package carries a runbook, not prose:**
  - *why* it's needed and *why it can't be automated* (a human-only boundary, not laziness);
  - **ordered steps**;
  - **exact CLI commands, one per line, copyable** — never "run the thing";
  - **sensitive values go into interactive prompts, never into a command the human edits** —
    the command names the key and lets the CLI prompt for the value, hidden where possible
    (`gh secret set NAME`, `vercel env add NAME`, `read -s`), so copyable lines never contain a
    secret and nothing lands in shell history/`ps`/logs; paste-into-command is a flagged last
    resort only when no interactive option exists;
  - **a committed, runnable script** where code must execute — not pasted snippets;
  - **official documentation links** for any vendor/UI step — never "go to settings in X";
  - **prerequisites** and a **verification step** (how completion is confirmed).
  The runbook is produced by the persona closest to the domain (Developer/Architect for CLI/infra; Head
  of FinOps for billing; Head of Security for registrar/secrets — fetching current vendor docs) and
  validated by the PM before it surfaces.

Both the decision and action shapes are **required-field checklists the cockpit validates** — an item
missing a field cannot enter `needs-human`. Completeness is enforced structurally, not by PM judgment
(same idea as the access lock and the acceptance-criteria contract).

### Tracking & verification
Actions are **tracked at step level** in the cockpit: each runbook is a checklist the human works
through; on "done," the system **verifies where it can** (env var present, key works, migration
applied) and only then flips the parked action to `ready`. The human is never the unverified link —
proof, applied gently to human work too. Outstanding decisions and actions **persist** in the cockpit
(and the daily scan); they never evaporate as chat afterthoughts.

Every step has a **failure path** routing straight back to the PM funnel — and it's a **captured** path,
not a composed one: the re-open **pre-fills** the failed step, the exact command run, and any visible
output, so a frustrated, out-of-context human **confirms** rather than writes prose (reusing the
copyable-command discipline). A human who isn't deep in the repo is never stranded on a failed step.

## Plugin architecture

Standard layout (`.claude-plugin/plugin.json` + a marketplace entry):

| Component | Contents |
|---|---|
| `agents/` | One agent per persona. **Briefing = system prompt; access lock = `tools:` whitelist.** Readers have no `Edit`/`Write`; Developer has full tools. This makes the access lock structural. |
| `commands/persona-init.md` | The **bootstrap** — runs the interview, writes the instance config. |
| `commands/persona.md` | Summon/dispatch launcher (replaces `bin/persona`); uses `claude --worktree` for the Developer. |
| `commands/decisions.md` | The human's cockpit — surfaces what's waiting on the human. |
| `skills/` + `_disciplines` | The shared disciplines, injected into every persona; the bootstrap skill; later a promote-to-platform skill. |

- **Model vs. instance:** the model (briefings, disciplines, agents) lives in the plugin so
  updates stay central; the **instance** (manifest, per-repo overrides, schedules, port
  range, worktree settings) is generated into the target repo's `.claude/persona-lab/`.
- **Summon** = use the agent interactively; **dispatch** = the Agent tool / headless
  `claude -p` + `--allowedTools` + auto mode for unattended runs, gated in-prompt → `/goal`
  → deterministic Stop hook.

## The four research upgrades, mapped

| Upgrade | Where it lands |
|---|---|
| Verification hierarchy + agent-runnable E2E gate | `_disciplines`; Developer briefing (UI/full-stack changes need a rendered-output/E2E check, not just typecheck+lint+tests — unit-tests-only on UI is the named false-completion trap) |
| Context hygiene (compaction + note-taking) | `_disciplines`; PM thread-compaction duty |
| Fan-out economics (~15× tokens) | `_disciplines`; PM dispatch trigger (auditor sweep = justified fan-out; else serialize) |
| Native tooling (`--worktree`, `/goal`, Stop hook, `-p`, `--allowedTools`, auto mode) | launcher + dispatch path; documented operating guidance |

## Build phases (dependency-ordered, each independently usable)

1. **Model-as-plugin, single-repo grain.** Plugin skeleton + persona agents with access
   locks + `_disciplines` + voice/tone specs + `/persona` launcher with worktrees + the bus
   discipline/envelope + the four upgrades baked into briefings. The **queue port over GitHub
   Issues** (with the dedup-at-creation fingerprint ledger + report-by-exception), a
   **PM-curated Projects v2 cockpit from day one**, and the **`/decisions`** command. Validate
   by hand-writing the manifest for one real repo (e.g. `finances`). **Outcome: usable
   personas in a real repo immediately.**
2. **The bootstrap (`/persona-init`).** The interview that generates the single-repo config.
   *Outcome: "installable, asks questions, then goes."*
3. **Platform tier.** Portfolio manifest, senior ranks + cross-app artifacts, cross-repo
   issue bus, home-base execution, the promotion flow, `/decisions` portfolio aggregation.
4. **Autonomous dispatch & scheduling.** `claude -p`, auto mode, Stop-hook gating, the
   GitHub App bot, scheduled ~9am cockpit scan + notification, fan-out economics enforced.

**Phase 1 is the recommended first slice to plan in detail.**

## Appendix A — bootstrap interview questions

1. Grain: single repo, or platform spanning multiple apps?
2. (if platform) which repos are members, and where is home base?
3. Human: who is the escalation target?
4. Bus: GitHub issues as the queue?
5. Roster: which disciplines are in scope (default minimal: Product Analyst + Developer; add
   architect/auditors only when chosen)? Propose a **name** for each (human can rename); repo
   personas get a distinct name per repo.
6. Per persona: trigger mix (summon-only / on-demand / scheduled / event — event named) +
   access lock.
7. Tooling: worktrees on? auto mode for unattended Developer? claim a port range?
8. Seed the platform PM's **delegation charter** conservatively (escalate-by-default); the PM
   proposes widening it over time as it learns the human's judgment, never without approval.
9. Daily **budget ceiling** (token/$) — hard-pause + alert at the limit; raising it is a human
   decision.
10. Repo visibility (public/private) — public repos treat all non-human/non-bot content as
    untrusted, quarantined to triage.
11. **Oversight profile** — visibility (minimal → observe-everything), involvement (delegation-charter
    breadth), cadence/channel; default minimal, adjustable anytime, overridable per domain/severity.

## Appendix B — primary sources informing the upgrades

- Anthropic — [Claude Code best practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- Anthropic — [Building agents with the Claude Agent SDK](https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk)
- Anthropic — [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- Anthropic — [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- Anthropic — [Multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)
- Anthropic — [How Anthropic teams use Claude Code (PDF)](https://www-cdn.anthropic.com/58284b19e702b49db9302d5b6f135ad8871e7658.pdf)
- Claude Code docs — [worktrees](https://code.claude.com/docs/en/worktrees)

## Open questions (deferred to phase planning)

- Exact `_disciplines` injection mechanism (shared-read vs. concatenation into each agent).
- Whether briefings are read from the plugin + manifest scope, or copied/customized into
  the repo (lean: plugin canonical + manifest override).
- Platform-tier execution home — where platform personas run and reach into member repos
  (Phase 3). (Bus substrate is decided: GitHub Issues store + Projects v2 cockpit, behind a
  queue port.)
- The dedup fingerprint-ledger implementation (in-repo index vs. label-encoded vs. a tiny
  state file) — Phase 1 detail.
- Scheduling + notification channel for the 9am cockpit scan (Phase 4).
- Manifest file format (YAML vs. Markdown table vs. JSON).
