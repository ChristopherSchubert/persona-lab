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

The roster has always been *platform-grained* (architect, librarian, design, security,
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
Senior rank = the strategist who owns the standard (*Maven / Manager / Architect*); junior
rank = the operator who applies it (*Analyst*). A paired discipline is **one briefing + a
rank delta**, not two documents — the delta *is* the decides-vs-escalates line.

**A junior rank exists only when there's repo-local work no other persona covers.**
Architecture and ontology have none — local design is the Developer's and planner's, and
ontology conformance is a drift audit the Product Analyst already runs — so both are
platform-only. Inventing a junior just for symmetry is the costume-role anti-pattern.

| Discipline | Platform rank | Repo rank | Shape |
|---|---|---|---|
| Product | **Product Manager** (portfolio roadmap, human funnel) | **Product Analyst** (local queue, acceptance/drift audits) | paired |
| Security | **Security Maven** (policy, registrar, incident cmd) | **Security Analyst** (local review, files up) | paired |
| Architecture | **Platform Architect** (cross-app contracts, ADRs) | none — Developer + planner cover local design; escalate contract/ADR changes up | platform-only |
| Design | **Design Maven** (the design system) | **Design Analyst** (local conformance) | paired |
| Build | — (no platform twin) | **Developer / writer** | repo-only |
| Ontology | **Data-model Librarian** (the one shared ontology) | none — Product Analyst drift-audits local conformance | platform-only |
| Cost | **Cost Watch** (account-level billing) | (local resource-growth check) | platform-leaning |
| Leak scan | (policy under Security) | **Leak Scanner** (scans this repo) | repo-leaning |

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
| **Repo / junior** | "Developer, how would you approach this?" | Developer implements an issue; Leak Scanner sweeps; Product Analyst grooms the local queue |

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
actor, outcome: acted|slept|escalated|blocked, actions[], declined:[{what,why}], links[],
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
   scope).
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

A fixed round-robin (Developer → Maven → …) makes every cross-persona handoff cost up to a full
lap. Instead, **the queue is the scheduler**: personas are dispatched by queue state and
cadence, in a pipeline ordered by dependency — **Sense → Triage → Act → Audit**, repeating:

1. **Sense** — auditors run (parallel fan-out, bounded + read-only) → findings to the queue.
2. **Triage** — the **PM** grooms: dedup, frame, prioritize, escalate owner-class to
   `/decisions`. The queue is now ordered and actionable.
3. **Act** — the **Developer runs a continuous inner loop**, draining the actionable queue
   (bugs first) under the writer lock until empty or budget-spent.
4. **Audit** — the PM acceptance-audits the closed work.

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
ready); Leak Scanner = scheduled(daily) + event(pre-commit); Architect = summon-only; PM =
scheduled(after sweeps) + on-demand. (Orchestration mechanism is built in Phase 4; this is the
model it implements.)

## The portfolio manifest

The team is declared, not ambient. One file (lives in the platform repo; trivial/absent for
single-repo) declares membership and a persona×repo **capacity matrix** from a small fixed
vocabulary: `owns` / `sets-standard` / `audits` / `advises` / `writer` / `reads` /
`not-engaged`. It is machine-readable — the launcher and dispatch read it to know who may
touch what.

```
platform: schubert
repos: [finances, schubert-family, livability-scout]
engagement:
  product-manager:    { all: owns(roadmap+funnel) }
  platform-architect: { all: owns(contracts+ADRs), reads: all }
  data-librarian:     { all: owns(ontology), reads: all }
  design-maven:       { all: sets-standard }
  security-maven:     { all: owns(policy+registrar) }
  cost-watch:         { all: owns(billing) }
  developer:          { per-repo: writer }
  product-analyst:    { per-repo: owns(local queue) }
  leak-scanner:       { per-repo: audits }
```

## Shared disciplines (`_disciplines`, injected into every persona)

1. **Verification hierarchy.** A close or finding needs *a check the persona can run
   itself*. Robustness order: **deterministic rules** (tests, build exit, linter,
   schema/diff) **> visual/rendered** (screenshot, browser E2E) **> LLM-as-judge** (least
   robust; weigh latency). "Looks done" is not done.
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

## Per-persona voice & tone

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
- **Security Maven** (blunt, risk-first): "Zero clock-skew tolerance in token verification
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
| **Product Manager** | calm, decisive, sequencing | a steady lead who turns a mess into a ranked list |
| **Product Analyst** | diligent, operational, close to the work | the PM's sharp junior keeping the local queue honest |
| **Platform Architect** | measured, systems-minded, long-view | someone who sees the migration coming six months early |
| **Design Maven** | opinionated, exacting about craft | a designer who twitches at three slightly different blues |
| **Design Analyst** | practical, detail-attentive | catches drift from the system, repo by repo |
| **Data-model Librarian** | meticulous, precise, lightly pedantic | a librarian who insists one thing has exactly one name |
| **Security Maven** | blunt, risk-first, severe | the one who says "rotate it now," not "consider rotating" |
| **Security Analyst** | careful, methodical, thorough | runs the checklist; escalates the severity call |
| **Leak Scanner** | factual, mechanical, evidence-only | a detector — location + match, no opinions |
| **Cost Watch** | dry, numbers-first, deadpan | an accountant who speaks in deltas and dollars |

Paired ranks share a discipline's tone; the senior is more declarative and strategic, the
analyst more operational. The **human's** own voice is the deliberate contrast: plain, brief,
authoritative — no AI banner, decisions not discussion — kept scarce so it carries weight.

## The issue bus discipline

- **Comments are typed, discrete state records — not conversation.** Vocabulary:
  `FINDING` · `PROPOSAL` · `DECISION` · `HANDOFF` · `PROOF` · `BLOCKED(needs-human)`. One
  self-contained record of a state transition per comment.
- **Personas do not converse in-thread.** No persona-to-persona dialogue (they already
  never talk directly). A persona posts a finding → PM frames → human decides. Dialogue is
  human↔PM only and terminates in a recorded decision.
- **The PM compacts noisy threads** — context-hygiene applied to the durable layer.
- **An issue's body is the contract; its comments are a short, signed, typed ledger.**

### Comment envelope (one header line + collapsed detail footer)

```markdown
🤖 **Developer** · FINDING

Login rejects valid credentials when the user's device clock runs >30s ahead of the server.

`verifyToken()` in `auth/session.ts` treats any JWT whose `iat` is in the future as forged
and returns 401 — it allows zero clock skew. Users on slightly-fast clocks hit "session
expired" on a correct password. Repro: set the system clock +45s, sign in → 401.

Proposed fix: a 60s `clockTolerance` in `verifyToken()` (RFC-7519 standard), pinned by a
regression test. Low blast radius. Implementing under this issue unless the architect flags
a contract concern.

<details><summary>AI persona — not the human</summary>
Developer · dispatched · 2026-06-21 · briefing ↗
</details>
```

- **Header (one line):** AI flag + persona + record type.
- **Body:** the concise record.
- **Footer (collapsed `<details>`):** provenance — mode, date, briefing link — present but
  uncluttering. Briefing link resolves to the canonical plugin file; manifest may override.
- **The human's own decisions get the inverse:** no robot banner, marked plainly as the
  human voice (`DECISION — human`), kept scarce so it carries weight.

### Substrate, governance & the cockpit

**Decision:** the bus is **GitHub Issues** as the store, behind a **queue port** (file /
comment / label / close / query) so the substrate is swappable without touching the model. A
**GitHub Projects v2 board is the cross-repo cockpit from day one**, curated by the platform
PM (the board is the PM's roadmap made visible). Evaluated against Linear (4/5) and a
Supabase/Postgres queue (4/5); Issues (4/5) won on cost (free), native git/PR co-location,
best off-the-shelf agent tooling (official MCP + `gh`), and audit semantics — and its two
weaknesses (no upsert; a ~500 content-writes/hour secondary cap) are exactly what the
governance below neutralizes. Supabase becomes the right answer only if idempotent dedup +
cross-repo analytics become core and owning a control plane is acceptable — cheap to switch
to later, via the port.

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
  this repo; Phase 3: portfolio + platform queue), renders them **PM-framed** (crisp options
  + recommendation, highest-leverage first), lets the human decide in-session, and records
  the decision durably. The raw queue stays one command away — curation never becomes
  concealment.
- **Opt-in session-start line:** a one-liner "N decisions waiting — run `/decisions`".
- **Optional scheduled ~9am scan (Phase 4):** runs the cockpit scan and notifies the human
  (channel TBD — push / iMessage / email).

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
   architect/auditors only when chosen)?
6. Per persona: trigger mix (summon-only / on-demand / scheduled / event — event named) +
   access lock.
7. Tooling: worktrees on? auto mode for unattended Developer? claim a port range?

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
