<div align="center">

<img src="assets/avatars/sarah/sarah-64.png" width="50" alt="Sarah">&nbsp;<img src="assets/avatars/greg/greg-64.png" width="50" alt="Greg">&nbsp;<img src="assets/avatars/tom/tom-64.png" width="50" alt="Tom">&nbsp;<img src="assets/avatars/raj/raj-64.png" width="50" alt="Raj">&nbsp;<img src="assets/avatars/mike/mike-64.png" width="50" alt="Mike">&nbsp;<img src="assets/avatars/laura/laura-64.png" width="50" alt="Laura">&nbsp;<img src="assets/avatars/dave/dave-64.png" width="50" alt="Dave">&nbsp;<img src="assets/avatars/ben/ben-64.png" width="50" alt="Ben">&nbsp;<img src="assets/avatars/zoe/zoe-64.png" width="50" alt="Zoe">&nbsp;<img src="assets/avatars/max/max-64.png" width="50" alt="Max">&nbsp;<img src="assets/avatars/esme/esme-64.png" width="50" alt="Esmé">

# Persona Lab

**A multi-persona operating model for single-human-driven, mostly-autonomous software development.**

Instead of one undifferentiated assistant, you get a *team* — distinct named personas, each with its own lens, a hard tool boundary, and a defined way to hand off. You drive; they do the legwork; only the calls that are genuinely yours come back up to you.

![version](https://img.shields.io/badge/version-0.1.0-3b82f6) &nbsp;![license](https://img.shields.io/badge/license-MIT-22c55e) &nbsp;![plugin](https://img.shields.io/badge/Claude%20Code-plugin-d97757)

</div>

---

## What it is

A [Claude Code](https://claude.com/claude-code) plugin. Install it into a repo, run `/persona-init`, answer a short interview, and the repo goes from empty to a working team: personas registered as access-locked subagents, a GitHub-issues bus, a writer lock, and a verification gate.

Three ideas do the heavy lifting:

- **Authority is separate from legwork — and escalation is built in.** Every persona has a bright line between what it may decide alone and what it must hand up. Money, direction, anything irreversible or outward-facing is *yours*; an AI persona that hits one of those calls is required to file it, framed, never to guess.
- **Personas are stateless.** None hold conversation context. Durable state lives in files and issues, so any persona reloads when it starts — which is what lets independent sessions and scheduled jobs coordinate without shared memory.
- **Access is structural, not aspirational.** "You can't fix what you found — you file an issue" is enforced by the tool whitelist, not by a reminder. Only the Developer persona has write tools.

---

## Meet the team

Two tiers. **Platform specialists** are singletons — one standing expert per discipline, working across all your repos. The **repo team** is instantiated per project, with names drawn from per-role pools, so your `finances` Developer is a different person from another repo's.

### Platform tier

| | Persona | Lens | Access |
|:--:|---|---|:--:|
| <img src="assets/avatars/sarah/sarah-64.png" width="44"> | **Sarah** · Product Manager | Grooms the queue, surfaces your decisions, audits closes | reader |
| <img src="assets/avatars/greg/greg-64.png" width="44"> | **Greg** · Lead Engineer | Owns code review and the verification gate | reader |
| <img src="assets/avatars/tom/tom-64.png" width="44"> | **Tom** · Platform Architect | Cross-app contracts, env topology, ADRs | reader |
| <img src="assets/avatars/raj/raj-64.png" width="44"> | **Raj** · Data Architect | The shared data model / domain ontology | reader |
| <img src="assets/avatars/mike/mike-64.png" width="44"> | **Mike** · Head of Security | Risk-first audits, rooted in real risk | auditor |
| <img src="assets/avatars/laura/laura-64.png" width="44"> | **Laura** · Head of Design | UX and design-system coherence | reader |
| <img src="assets/avatars/dave/dave-64.png" width="44"> | **Dave** · Head of FinOps | Guards the spend, per dollar and per token | reader |

### Repo team — example: `finances`

| | Persona | Lens | Access |
|:--:|---|---|:--:|
| <img src="assets/avatars/ben/ben-64.png" width="44"> | **Ben** · Developer | Implements one issue end-to-end | **writer** |
| <img src="assets/avatars/zoe/zoe-64.png" width="44"> | **Zoe** · Product Analyst | Triages the queue, writes acceptance criteria | reader |
| <img src="assets/avatars/max/max-64.png" width="44"> | **Max** · Security Analyst | Scans diffs for real, exploitable risk | auditor |
| <img src="assets/avatars/esme/esme-64.png" width="44"> | **Esmé** · Design Analyst | Checks UI against the design system | reader |

**Access** is the lock, not a personality trait:

- **writer** — the single actor allowed to mutate app code at any one time. The Developer takes this lock; no one else has edit tools.
- **auditor** — read + run (can execute scans and tests), never write.
- **reader** — read-only.

Briefings live in [`docs/personas/`](docs/personas/); start from [`_template.md`](docs/personas/_template.md) to add your own. Names are proposed defaults from [`_name-pools.md`](docs/personas/_name-pools.md) — rename anyone at any time; the role's authority and access never change.

---

## How it works

### The loop

```
You ──▶ Sarah (files & grooms) ──▶ Ben (builds, holds the lock) ──▶ Greg (reviews at the gate) ──▶ shipped, proof attached
 ▲                                                                                                        │
 └──────────────────────── only the calls that are genuinely yours loop back up ─────────────────────────┘
```

You stay the driver. The team runs the queue. Everything the team can close on its own, it closes; the rest is funneled to you as framed decisions.

### The bus: GitHub issues

Personas never talk to each other directly. The issue tracker *is* the bus — **open = the live queue, closed = the audit trail**. Every cross-persona message is a **typed record** that stands alone (the next stateless session has none of your context):

`FINDING` · `PROPOSAL` · `DECISION` · `HANDOFF` · `PROOF` · `REVIEW` · `BLOCKED`

Each comment carries an envelope so a human skimming the thread sees who said what, in what capacity — with their face:

> <img src="assets/avatars/ben/ben-64.png" width="18"> 🤖 **Ben** (repo · Developer) · **PROOF**
>
> Added a 60s leeway window to the `iat` check. 14 tests green, including skew cases. Verified against `HEAD a1b2c3d`; diff +18/−4, within budget.
>
> <details><summary>run metadata</summary>model: claude-opus-4-8 · run: 2026-06-26T14:21Z · tokens: 9.7k</details>

### The writer lock

At most one Developer mutates the tree at a time. The lock is a **create-only** claim on a real git branch carrying `{holder, claimed_at, fence}` — no force-pushes, ever. The fence (a commit SHA) is re-read fresh before any integrate, so a stale writer can't clobber newer work. Readers run freely alongside.

### The verification gate

A close is **proof, not permission**. `gate.sh` blocks self-close and requires a verification marker plus an approved `REVIEW` that cites the current `HEAD` and stays within the diff budget. "Looks done" doesn't close an issue; cited, rendered-output evidence does.

### Governance: conservative by default

Autonomy is **escalate-by-default** and **opt-in** — there is no auto-mode at install. Visibility defaults to minimal. The spectrum is supported (some humans want to review everything, some want only the decisions), but the safe end is the default, deliberately.

---

## Install

1. Add the plugin to Claude Code (this repo is a plugin — see [`.claude-plugin/`](.claude-plugin/)).
2. In your target repo, run:
   ```
   /persona-init
   ```
   A short interview asks the operating questions (which disciplines are in scope, each persona's cadence, the daily budget ceiling, proposed names). Sensitive values are requested via interactive prompts — never pasted into a command.
3. It generates the instance config, provisions the issue labels, and builds the access-locked agents. Then drive it:
   - `/persona <name>` — summon a persona into your session to advise (no lock taken).
   - `/inbox` — your cockpit: what's waiting on *you*, framed, with recommendations.

---

## Two tiers, one model

The same model scales by **grain**:

- **Single repo** — the platform tier collapses; you run just the repo team. No overkill.
- **Second app** — promote with `scripts/promote.sh`. The platform specialists (Tom, Raj, Mike, …) graduate in to own the cross-app contracts, while each repo keeps its own Developer and analysts.

---

## Layout

```
.claude-plugin/   plugin.json + marketplace.json
agents/           built subagents (one per persona; tool whitelist = the access lock)
commands/         /persona-init, /persona, /inbox
scripts/          the machinery — lock.sh, gate.sh, queue.sh, dedup.sh, runlog.sh,
                  build-agents.sh, init.sh, assign-names.sh, promote.sh, watchdog.sh, …
config/           capability-map.json, schemas/ (typed records), copy.json, manifest.example.yml
docs/personas/    one briefing per persona (human.md is the charter the rest read)
assets/avatars/   per-individual pixel avatars (67 names × 4 sizes)
tests/            bats suite (run: `bats tests/`)
bin/persona       launcher
```

---

## Status

Phases 1–4 built and merged: the model-as-plugin, the `/persona-init` bootstrap, the platform-tier core, and the orchestration core (lock / gate / queue / dedup / run-log / watchdog), plus the 67-persona avatar set. The Bats suite is green. Live enablement of fully-autonomous dispatch is opt-in and being hardened — the human-in-the-loop guarantee is on by default.

## License

MIT.
