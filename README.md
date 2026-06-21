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
are briefings an AI session loads.

| # | Persona | Lens | Launch mode | Can edit |
|---|---------|------|-------------|----------|
| — | **Owner** (you) | Product authority | n/a (the human) | anything |
| 1 | **PM** | Backlog, roadmap, audits, the escalation funnel | interactive | issues only (propose) |
| 2 | **Writer** | Implements one issue end-to-end | interactive (worktree) | app code |
| 3 | **Platform architect** | Cross-app contracts, env topology, DNS, ADRs | interactive | docs/ADRs |
| 4 | **Design maven** | Design-language coherence across apps | dispatched | read-only |
| 5 | **Data-model librarian** | Shared domain nouns (the common ontology) | dispatched | read-only |
| 6 | **Security maven** | Security review + registrar account | dispatched | read-only |
| 7 | **Leak scanner** | Accidentally-stored info (secrets, PII, account refs) | dispatched / scheduled | read-only |
| 8 | **Cost watch** | Hosting/DB tiers, spend, resource growth | dispatched / scheduled | read-only |

The briefings live in [`docs/personas/`](docs/personas/). Start from
[`_template.md`](docs/personas/_template.md) to add your own.

## Two axes that actually matter

There is **no "standing" persona** — none hold persistent context. Durable state lives in files and
issues, so every persona reloads when it starts. What distinguishes them is:

1. **Who launches it** — *interactive* (a human opens it as a session) vs. *dispatched* (the PM
   fans it out via the assistant's sub-agent mechanism, or a cron job runs it headless).
2. **What it can edit** — the writer edits app code, the architect edits docs, the PM proposes on
   issues, the scanners edit nothing. Auditor personas should literally **lack edit/write tools**,
   so "you can't fix what you found — you file an issue" is structural, not aspirational.

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
bin/persona      launcher: injects a briefing into an interactive AI session
```

## Adopting this in your project

1. Copy `docs/personas/` and edit each briefing to your project's reality.
2. Decide which personas are interactive vs. dispatched.
3. Wire the launcher (or your assistant's equivalent) and any scheduled jobs.
4. Route all handoffs through your issue tracker.

## Status

A template / reference model. The owner and PM briefings are the load-bearing pieces — they encode
the escalation contract. The other six are example briefings to adapt.

## License

Choose one before publishing (e.g. MIT for a permissive methodology repo). Not included by default.
