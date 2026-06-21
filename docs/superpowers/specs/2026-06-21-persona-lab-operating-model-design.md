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

| Discipline | Platform rank | Repo rank | Shape |
|---|---|---|---|
| Product | **Product Manager** (portfolio roadmap, human funnel) | **Product Analyst** (local queue, acceptance/drift audits) | paired |
| Security | **Security Maven** (policy, registrar, incident cmd) | **Security Analyst** (local review, files up) | paired |
| Architecture | **Platform Architect** (cross-app contracts, ADRs) | (often folded into Developer/planner) | paired, light repo rank |
| Design | **Design Maven** (the design system) | **Design Analyst** (local conformance) | paired |
| Build | — (no platform twin) | **Developer / writer** | repo-only |
| Ontology | **Data-model Librarian** (the one shared ontology) | (repo consumes + reports drift) | platform-only |
| Cost | **Cost Watch** (account-level billing) | (local resource-growth check) | platform-leaning |
| Leak scan | (policy under Security) | **Leak Scanner** (scans this repo) | repo-leaning |

### Avoiding overkill — by construction

1. **Personas are invoked, not staffed.** An uninstantiated persona costs nothing; cost
   comes from invocation, not from existing on a chart.
2. **A single repo runs the repo tier only** — platform responsibilities collapse upward
   into the human. With one app, *you are* the platform tier.
3. **The platform tier is promoted into existence by the first real cross-app concern** (a
   second app, a shared noun, a shared design token, a second domain) — never before.
4. **The bootstrap interview decides the grain at install**, so a single-repo project never
   sees the platform machinery.

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

## Per-persona voice

Each persona writes like a real person doing that job — distinct diction and framing — but
**voice lives in word choice, never word count.** A persona in character is still terse. The
envelope *names* the persona; the voice *confirms* it. Each briefing carries a one-line
voice spec (2–3 traits + register). Examples (same finding, all tight):

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
   locks + `_disciplines` + voice specs + `/persona` launcher with worktrees + the bus
   discipline/envelope + the four upgrades baked into briefings. Validate by hand-writing
   the manifest for one real repo (e.g. `finances`). **Outcome: usable personas in a real
   repo immediately.**
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
6. Per persona: cadence (summon-only / dispatched-on-demand / scheduled) + access lock.
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
- Cross-repo issue-bus mechanics and platform-tier execution home (Phase 3).
- Scheduling + notification channel for the 9am cockpit scan (Phase 4).
- Manifest file format (YAML vs. Markdown table vs. JSON).
