# persona-lab

A lightweight **multi-persona operating model** for running a software project — especially a
multi-app platform — with an AI coding assistant like [Claude Code](https://claude.com/claude-code).
Instead of one undifferentiated "assistant," work is split across **personas**: distinct lenses,
each with a clear scope, a tool boundary, and a defined way to hand off.

It's aimed at a **solo developer or small team** where one human is the product owner and an AI
does most of the legwork across several roles — but the separation of concerns generalizes to any
team.

**The defining feature: escalation back to a human is built in.** Every persona has a bright line
between what it may decide on its own and what it must hand up. Owner-class calls — money,
direction, anything irreversible — don't get silently defaulted by an AI; they route, framed, to a
human who decides. The model is human-in-the-loop *by construction*, not by reminder.

## Why personas

A persona earns its place only if it has a **lens or a data source nobody else is looking at**. If
a proposed role is really just someone's definition-of-done wearing a costume (QA, ops, docs, a
generic "release engineer"), it isn't a persona — fold it into an existing role.

Two ideas do the heavy lifting:

1. **Separate authority from legwork, with escalation built in.** The **owner** (a human) holds
   product authority — money, direction, anything irreversible or outward-facing. Every other
   persona does the work and *escalates* owner-class decisions rather than making them. The
   escalation isn't an optional courtesy — it's part of each persona's contract: a defined
   "decides vs. escalates" boundary, and a routing path that ends at a human. An AI persona that
   hits an owner-class call is *required* to hand up, framed, never to guess.
2. **Personas are stateless.** None hold persistent conversation context. Durable state lives in
   **files and issues**, so any persona reloads its state when it starts. That's what lets
   independent sessions — or scheduled jobs — coordinate without shared memory.

## The example personas

A **starter set** — rename and re-scope to fit your project. The owner is you, the human; the rest
are **subagents** — each a briefing + a tool scope (see "One mechanism" below).

`Access` is the read/write **lock**, not a persona trait: the **writer** is the single actor
allowed to mutate app code at a time; everyone else is a **reader**. The Developer is the persona
that takes the writer lock.

| # | Persona | Lens | Access | Typically |
|---|---------|------|--------|-----------|
| — | **Owner** (you) | Product authority | — (the human) | the session you drive |
| 1 | **PM** | Backlog, roadmap, audits, the escalation funnel | reader + issues | dispatched or summoned |
| 2 | **Developer** | Implements one issue end-to-end | **writer** (app code) | dispatched, autonomous |
| 3 | **Platform architect** | Cross-app contracts, env topology, DNS, ADRs | reader + docs | summoned; authors ADRs |
| 4 | **Design maven** | Design-language coherence across apps | reader | dispatched / scheduled |
| 5 | **Data-model librarian** | Shared domain nouns (the common ontology) | reader | dispatched / scheduled |
| 6 | **Security maven** | Security review + registrar account | reader | dispatched / scheduled |
| 7 | **Leak scanner** | Accidentally-stored info (secrets, PII, account refs) | reader | dispatched / scheduled |
| 8 | **Cost watch** | Hosting/DB tiers, spend, resource growth | reader | dispatched / scheduled |

The briefings live in [`docs/personas/`](docs/personas/). Start from
[`_template.md`](docs/personas/_template.md) to add your own.

## One mechanism, two ways to invoke

There is **no "interactive vs. autonomous" persona** and **no "standing" persona**. Every persona
(except the owner) is the *same kind of thing*: a **subagent** — a briefing + a tool scope, with no
persistent conversation context. Durable state lives in **files and issues**, so any persona
reloads when it starts. What varies is only *how you invoke* a given subagent:

1. **Dispatched** — runs **autonomously to do its work**: the Developer implements an issue
   end-to-end; the leak scanner runs its sweep; the PM grooms the queue. No human stepping through
   it; results land as commits and issues. May run on demand or on a schedule.
2. **Summoned** — pulled into the **owner's interactive session to advise**: "bring in the
   architect — does this break a contract?" It answers or suggests back to the owner; it does not
   act.

Escalation-to-a-human survives in **both** modes: a summoned persona advises the owner directly; a
dispatched persona escalates owner-class calls via the PM and issues. The human-in-the-loop
guarantee is a property of the *contract*, not of how the subagent was launched.

The one real per-persona axis is **access** (the lock): the Developer holds the **writer** lock and
is the sole code-mutator; auditor personas are **readers** that should literally **lack edit/write
tools**, so "you can't fix what you found — you file an issue" is structural, not aspirational.

## Escalation: the PM is the funnel

Personas do **not** all escalate to the owner directly — that makes the owner a fan-in bottleneck
flooded with half-framed asks. Two paths:

- **Default path** — a persona's output is a *finding* or *proposal*, not a decision. It becomes an
  **issue**. The PM grooms, dedups, and frames the genuinely owner-class items, and brings the
  owner **one curated stream** with options + a recommendation.
- **Incident path** — a narrow bypass for *time-critical + high-blast-radius* only (active registrar
  hijack, live leaked credential, real PII publicly exposed). These page the owner directly, PM
  cc'd.

The PM funnels **decisions**, not **information**: the issue tracker stays open, so the owner can
always read the raw queue and catch anything the PM filtered.

## Handoff is issues-only

Personas never talk to each other directly. The issue tracker is the bus: **open = the live queue,
closed = the audit trail**. This is what lets stateless personas coordinate.

## Layout

```
docs/personas/   one briefing per persona (owner.md is the charter the others read)
  _template.md   shape for a new persona
bin/persona      launcher: summon a persona into a focused interactive session
```

## Adopting this in your project

1. Copy `docs/personas/` and edit each briefing to your project's reality.
2. Register each persona as a subagent your assistant can load (e.g. a `.claude/agents/` entry
   that carries the briefing as its system prompt and the access scope as its tool whitelist).
3. Decide each persona's default cadence — dispatched on demand, scheduled, or summon-only — but
   remember any of them can also be summoned into a session to advise.
4. Route all handoffs through your issue tracker.

## Status

A template / reference model. The owner and PM briefings are the load-bearing pieces — they encode
the escalation contract. The other six are example briefings to adapt.

## License

Choose one before publishing (e.g. MIT for a permissive methodology repo). Not included by default.
