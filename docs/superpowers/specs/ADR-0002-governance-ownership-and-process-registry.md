# ADR-0002: Governance — Decision-Ownership Map and Process Registry

**Status:** Accepted  
**Date:** 2026-06-27  
**Owners:** Tom (Platform Architect) · Raj (Data Architect)

---

## Context

ADR-0001 settles the issue lifecycle state machine and introduces two governance record types —
`ROUTING` and `PUSHBACK` — that route contested decisions to their *owner-of-record*. It defers
to this ADR for: (a) the explicit, exhaustive map of which decision class belongs to which
owner-of-record, and (b) a structured, queryable home for processes that *must* happen — the
rows whose absence is itself a governance gap.

Without a decision-ownership map, the `ROUTING.rationale` field has nothing to cite, every
`PUSHBACK` resolution is ad-hoc (power-based rather than rule-based), and there is no
authoritative answer to "who decides this?" Without a process registry, calibration, sweep
liveness, and registry maintenance are undisciplined — they exist in prose but not as
machine-checkable invariants that the sweep can assert on cadence.

This ADR governs both. It is the single source of truth that `ROUTING` records cite, and the
schema against which the sweep checks that required processes are alive.

Two complementary parts:

- **Part 1 — Decision-Ownership Map:** who decides what, with resolution authority for disputes.
- **Part 2 — Process Registry:** what must happen, when, by whom, and how we know it ran.

---

## Decision

### Part 1 — Decision-Ownership Map

#### 1.1 Map table

Each row is a *decision class* — a category of decisions that arise on the bus. The **Owner
Role** is the owner-of-record who adjudicates a `PUSHBACK` in that class. The **Resolution
Authority** column names who steps in if the owner-of-record is the challenger, or if the
first facilitation cycle fails.

| # | Decision Class | Owner Role | Description / Examples | Resolution Authority |
|---|---|---|---|---|
| 1 | Terminology / taxonomy | Data Architect | Canonical record names (e.g. `REVIEW` vs `FEEDBACK`), label vocabulary, field-name conventions, data-type choices, schema naming | Owner adjudicates; if Owner is challenger → PM facilitates between Data Architect and Platform Architect; human is backstop after two cycles |
| 2 | State-machine / data contracts | Platform Architect + Data Architect (jointly) | State names, transitions, guard conditions, required-field schemas, record field definitions, wire formats | Joint owners must agree; if split → PM facilitates; human is backstop after two cycles |
| 3 | Product naming / taste / UX copy | Founder (human) | Public-facing names, product voice, brand decisions, persona names and personalities, aesthetic choices | Human is primary; no delegation; PM may prepare a `PROPOSAL` but the `DECISION` is always `DECISION — human` |
| 4 | Process / workflow | PM | Issue-queue workflow steps, triage rules, facilitation procedures, cadence of human-facing reviews, on-call rotation | PM adjudicates; if PM is challenger → Platform Architect and Data Architect jointly facilitate; human is backstop after two cycles |
| 5 | Infrastructure / runtime | Platform Architect | Hosting topology, port allocation, CI runner config, lock mechanism, sweep scheduling, GitHub App bot design, secrets management | Owner adjudicates; if Owner is challenger → PM facilitates between Platform Architect and Data Architect; human is backstop after two cycles |
| 6 | Release / git workflow / CI-CD | Release Engineer | Branch strategy, commit conventions, merge rules, tag/release cadence, pre-commit hooks, CI pipeline steps | Owner adjudicates; if Owner is challenger → PM facilitates; human is backstop after two cycles |
| 7 | Unclassified | PM (triage) | Any decision whose class is not listed in this map; PM triages to the correct class and routes, or flags a gap issue | PM triages; PM does NOT escalate unclassified decisions directly to Founder — triage first, escalate only if classification itself requires human judgment |

**Gap invariant:** a decision class missing from this map is a flaggable gap — the sweep (or any
persona) may file a gap issue (`ASSESSMENT` record, class: `governance-gap`) against this ADR. A
missing class is never an implicit assumption; the PM triages the gap issue and proposes a new
map row via the amendment procedure.

#### 1.2 Resolution authority — full procedure

1. A `PUSHBACK` record is filed against a `ROUTING`, citing the `ROUTING` foreign key, the
   `contested_class`, the `proposed_class`, and the `rationale` (must cite this map's row
   numbers).
2. The `ROUTING.status` moves to `contested`; all action on that routing halts (ADR-0001,
   Invariant 11).
3. The **owner-of-record** for the `contested_class` (per the map above) adjudicates within one
   sweep cadence. Their ruling is recorded as a `DECISION` record; the `ROUTING.status` moves to
   `resolved`.
4. If the **challenger is the owner-of-record**, the **PM facilitates** between the two closest
   owners (nearest adjacent rows in the map). Facilitation cycle 1 is a structured `ASK`
   / `REPLY` exchange with a deadline of two sweep cadences.
5. If facilitation cycle 1 fails (no agreement after deadline), **facilitation cycle 2** begins
   with a fresh deadline. The PM files an `BLOCKER` record naming the split.
6. If facilitation cycle 2 fails, the **human is the backstop**: the PM files a `PROPOSAL`
   record via the `ADMIT` transition (`needs_human`, `subtype: decision`) with the full options
   and the PM's recommendation. The human's `DECISION — human` record is final and non-appealable
   in that instance.
7. **The orchestrator may only file a `PUSHBACK` and halt.** The orchestrator never adjudicates
   a class, never routes a decision to itself, and never resumes work on a contested routing
   without a `resolved` status on the `ROUTING` record.

#### 1.3 Amendment procedure

The ownership map may only be amended by the Founder (human). Amendment procedure:

1. Any persona or the PM may propose an amendment by filing a `PROPOSAL` record via
   `needs_human` (`subtype: decision`, `deadline` required).
2. The human records a `DECISION — human`; the PM updates this ADR in a follow-up commit, records
   the amendment as a new revision line in the header block, and cross-links the issue.
3. All open `ROUTING` records that cited the amended row must be re-evaluated; the PM files
   `BLOCKER` records on any that are now misrouted, and `PUSHBACK` records are not required
   for re-routing (the amendment is the authority).
4. The amendment is effective from the commit timestamp; prior `ROUTING` records that resolved
   under the old map are not retroactively invalidated.

---

### Part 2 — Process Registry

#### 2.1 Purpose

The process registry is the structured, queryable home for "things that must happen." Each row
is a process that the system is obligated to run. A row's *absence* is a flaggable gap (same
gap-issue mechanic as the ownership map). At its trigger, a row is instantiated as a filed issue
(owner + deadline + state); the no-float invariant (ADR-0001, Invariant 1) owns it from that
point; the sweep asserts the row's invariant on cadence and escalates overdue instances to
`needs_human`.

The registry is self-governing: its own maintenance is row PR-003.

#### 2.2 Schema

Each row in the registry has the following fields:

| Field | Type | Description |
|---|---|---|
| `process_id` | `PR-NNN` | Stable identifier; never reused if a row is retired |
| `name` | string | Human-readable process name |
| `owner_role` | string | Role responsible for executing the process (must match a role in the ownership map or be `human`) |
| `trigger` | `event \| schedule \| condition` | What instantiates this process |
| `cadence_when` | string | ISO-8601 duration or cron expression or condition prose |
| `required_record` | SCREAMING_SNAKE | The record type that proves the process ran; must be present in ADR-0001's record taxonomy or declared here |
| `invariant` | string | A checkable boolean proposition the sweep asserts on cadence; must be falsifiable |

**New record type declared here:** `FEEDBACK` — one per in-scope role per `project_init`
event; fields: `{role, calibrated_by, timestamp, scope_acknowledged: bool, notes}`. This record
type is additive to ADR-0001's taxonomy; ADR-0001 is not amended — the taxonomy is extended here
and both ADRs cross-reference.

#### 2.3 Initial registry rows

| process_id | name | owner_role | trigger | cadence / when | required_record | invariant |
|---|---|---|---|---|---|---|
| PR-001 | Role calibration | PM | `event: project_init` | Within `init + 5 days` | `FEEDBACK` | `∀ role ∈ in_scope_roles → ∃ FEEDBACK(role=role, timestamp ≤ init+5d)` — if any role is missing a note past the deadline, sweep escalates that role to `needs_human` (subtype: action, deadline: now + 1 day) |
| PR-002 | Sweep-liveness watchdog | Platform Architect | `schedule: every sweep_cadence` | Every sweep run | `HANDOFF` (heartbeat variant, `heartbeat: true`) | `∃ HANDOFF(heartbeat=true, timestamp ≥ now − 2×sweep_cadence)` — if no heartbeat record exists within two cadences, the dead-man check fires: an external monitor (cron or GitHub Actions scheduled job) files a `ASSESSMENT` record with `blocker_type: infrastructure`, owner: Platform Architect, and the PM escalates to `needs_human`; the sweep is down until confirmed restored |
| PR-003 | Registry maintenance | PM | `event: map_amendment \| schedule: quarterly` | Within 5 days of any ownership-map amendment; or quarterly review | `DECISION` (registry-review variant) | `∃ DECISION(registry_review=true, timestamp ≤ last_amendment+5d OR timestamp ≤ last_quarterly_review+90d)` — if the registry has not been reviewed within 90 days and no amendment has triggered an earlier review, sweep escalates to `needs_human` (subtype: action, deadline: now + 7 days) |
| PR-004 | Gap-issue triage | PM | `condition: governance-gap issue filed` | Within one sweep cadence of filing | `DECISION` (gap-triage variant) | `∀ open issue(label=governance-gap) → ∃ DECISION(gap_triage=true, timestamp ≤ filed_at + sweep_cadence)` — untriaged gap issues past one cadence are escalated by the sweep to `needs_human` (subtype: decision, deadline: now + 1 day) |

#### 2.4 Process registry invariants

1. **Every process row has a stable `process_id`.** IDs are never reused. A retired row is
   marked `retired: true` with a retirement timestamp and a cross-reference to the gap issue or
   amendment that retired it; the row is kept in the registry (not deleted) for audit-trail
   purposes.

2. **A row's `required_record` must exist in the record taxonomy** (ADR-0001's taxonomy extended
   by this ADR). A row whose `required_record` names an undefined record type is itself a
   governance gap; the sweep flags it.

3. **The sweep-liveness watchdog (PR-002) is self-referential.** Its heartbeat is the proof that
   the sweep ran. If PR-002's invariant fails, all other sweep-asserted invariants are
   unverified. The dead-man check (an external monitor independent of the sweep) is the fallback.
   The Platform Architect owns the dead-man check mechanism; its liveness is a separate
   operational concern documented in the runbook (cross-linked from PR-002's issue instance).

4. **PR-001 (calibration) is a prerequisite for all other processes.** No process row may be
   instantiated as a live issue in a project until PR-001's invariant is satisfied (all in-scope
   roles have `FEEDBACK` records). The sweep enforces this ordering: it checks PR-001
   first on each run; if the invariant fails and the deadline has passed, it halts instantiation
   of new process issues until the gap is resolved.

5. **A missing row is a flaggable gap.** If a process is observed to recur on the bus but has no
   registry row, any persona may file a gap issue. The PM triages within one sweep cadence
   (PR-004 governs this). The gap is not implicitly assumed to be out-of-scope.

---

## Machine-readable spec

```json
{
  "version": "1.0.0",
  "adr": "ADR-0002",
  "references": ["ADR-0001"],
  "decision_ownership_map": {
    "version": "1.0.0",
    "amendment_authority": "human (Founder)",
    "gap_record": "ASSESSMENT with label governance-gap",
    "classes": [
      {
        "id": 1,
        "class": "terminology_taxonomy",
        "owner_role": "Data Architect",
        "examples": ["record names", "label vocabulary", "field-name conventions", "schema naming"],
        "resolution_if_owner_is_challenger": "PM facilitates between Data Architect and Platform Architect",
        "backstop": "human after two facilitation cycles"
      },
      {
        "id": 2,
        "class": "state_machine_data_contracts",
        "owner_role": ["Platform Architect", "Data Architect"],
        "ownership": "joint",
        "examples": ["state names", "transitions", "guard conditions", "required-field schemas", "record field definitions", "wire formats"],
        "resolution_if_split": "PM facilitates",
        "backstop": "human after two facilitation cycles"
      },
      {
        "id": 3,
        "class": "product_naming_taste_ux_copy",
        "owner_role": "human (Founder)",
        "examples": ["public-facing names", "product voice", "brand decisions", "persona names", "aesthetic choices"],
        "resolution_if_owner_is_challenger": "N/A — human is always primary; no delegation",
        "backstop": "N/A"
      },
      {
        "id": 4,
        "class": "process_workflow",
        "owner_role": "PM",
        "examples": ["queue workflow steps", "triage rules", "facilitation procedures", "cadence of human-facing reviews"],
        "resolution_if_owner_is_challenger": "Platform Architect and Data Architect jointly facilitate",
        "backstop": "human after two facilitation cycles"
      },
      {
        "id": 5,
        "class": "infrastructure_runtime",
        "owner_role": "Platform Architect",
        "examples": ["hosting topology", "port allocation", "CI runner config", "lock mechanism", "sweep scheduling", "secrets management"],
        "resolution_if_owner_is_challenger": "PM facilitates between Platform Architect and Data Architect",
        "backstop": "human after two facilitation cycles"
      },
      {
        "id": 6,
        "class": "release_git_workflow_cicd",
        "owner_role": "Release Engineer",
        "examples": ["branch strategy", "commit conventions", "merge rules", "tag/release cadence", "pre-commit hooks", "CI pipeline steps"],
        "resolution_if_owner_is_challenger": "PM facilitates",
        "backstop": "human after two facilitation cycles"
      },
      {
        "id": 7,
        "class": "unclassified",
        "owner_role": "PM (triage)",
        "examples": ["any decision whose class is not listed in this map"],
        "resolution": "PM triages to correct class; does NOT escalate directly to human without classification attempt first",
        "gap_action": "PM files gap issue if no class fits; proposes new row via amendment procedure"
      }
    ]
  },
  "process_registry": {
    "schema_version": "1.0.0",
    "new_record_types": [
      {
        "name": "FEEDBACK",
        "description": "One per in-scope role per project_init; proves the role was calibrated at project start",
        "fields": ["role", "calibrated_by", "timestamp", "scope_acknowledged", "notes"],
        "declared_in": "ADR-0002",
        "extends_taxonomy_from": "ADR-0001"
      }
    ],
    "rows": [
      {
        "process_id": "PR-001",
        "name": "Role calibration",
        "owner_role": "PM",
        "trigger": {"type": "event", "event": "project_init"},
        "cadence_when": "within init + P5D",
        "required_record": "FEEDBACK",
        "invariant": "forall role in in_scope_roles: exists FEEDBACK where role=role and timestamp <= init+P5D",
        "on_fail": "sweep escalates missing role to needs_human(subtype=action, deadline=now+P1D)",
        "prerequisite_for": "all other PR rows"
      },
      {
        "process_id": "PR-002",
        "name": "Sweep-liveness watchdog",
        "owner_role": "Platform Architect",
        "trigger": {"type": "schedule", "cron": "every sweep_cadence"},
        "cadence_when": "every sweep run",
        "required_record": "HANDOFF",
        "required_record_variant": {"heartbeat": true},
        "invariant": "exists HANDOFF where heartbeat=true and timestamp >= now - 2*sweep_cadence",
        "on_fail": "external dead-man check fires ASSESSMENT(blocker_type=infrastructure, owner=Platform Architect); PM escalates to needs_human",
        "note": "dead-man check is external to the sweep; its runbook is cross-linked from PR-002 issue instance"
      },
      {
        "process_id": "PR-003",
        "name": "Registry maintenance",
        "owner_role": "PM",
        "trigger": {"type": "event_or_schedule", "event": "map_amendment", "schedule": "quarterly (P90D)"},
        "cadence_when": "within 5 days of amendment; or within 90 days of last review",
        "required_record": "DECISION",
        "required_record_variant": {"registry_review": true},
        "invariant": "exists DECISION where registry_review=true and (timestamp <= last_amendment+P5D OR timestamp <= last_quarterly_review+P90D)",
        "on_fail": "sweep escalates to needs_human(subtype=action, deadline=now+P7D)"
      },
      {
        "process_id": "PR-004",
        "name": "Gap-issue triage",
        "owner_role": "PM",
        "trigger": {"type": "condition", "condition": "issue filed with label=governance-gap"},
        "cadence_when": "within one sweep cadence of filing",
        "required_record": "DECISION",
        "required_record_variant": {"gap_triage": true},
        "invariant": "forall open_issue where label=governance-gap: exists DECISION where gap_triage=true and timestamp <= issue.filed_at + sweep_cadence",
        "on_fail": "sweep escalates to needs_human(subtype=decision, deadline=now+P1D)"
      }
    ]
  }
}
```

---

## Amended record taxonomy (additive)

This ADR adds one record type to the taxonomy established in ADR-0001. ADR-0001 is not amended;
both ADRs cross-reference. The full effective taxonomy is ADR-0001's table plus the row below.

| Record | Purpose | Declared in |
|---|---|---|
| `FEEDBACK` | One per in-scope role per `project_init`; fields: `{role, calibrated_by, timestamp, scope_acknowledged: bool, notes}`; proves the role was calibrated at project start | ADR-0002 |

---

## Invariants

### Ownership-map invariants

1. **Every contested `ROUTING` cites a map row.** A `ROUTING` record's `rationale` field must
   cite a row number from this map's table. A `ROUTING` without a valid row citation fails the
   transition guard on `ROUTE`.

2. **Unclassified decisions are triaged, not assumed.** The `unclassified` row (class 7) is not a
   catch-all that resolves to "PM decides." The PM must produce a `DECISION` record that names the
   correct class and reroutes, or files a gap issue. The PM may not use class 7 as a permanent
   routing destination.

3. **Class 3 (product naming / taste) is human-only.** No persona may record a `DECISION` of
   class 3 — only `DECISION — human`. A persona-authored decision on a class 3 item is void and
   must be re-filed as `PROPOSAL` → `needs_human`.

4. **The map is append-only between amendments.** No row may be modified or deleted except via
   the amendment procedure (section 1.3). The map version field increments on each amendment.

5. **A gap issue is filed, not silently assumed.** If any persona or the sweep encounters a
   decision that does not fit any map row, a gap issue is filed (`ASSESSMENT`, `label:
   governance-gap`) before the decision proceeds. No decision proceeds under an implicit
   unmapped class.

### Process-registry invariants

6. **PR-001 gates all other process instantiation.** Until PR-001's invariant is satisfied (all
   in-scope roles have `FEEDBACK` records within the deadline), no other process row may
   be instantiated as a live issue.

7. **PR-002's heartbeat is the sweep's proof of life.** The sweep writes a `HANDOFF(heartbeat=true)`
   record as its first action on each run. If two consecutive heartbeat windows pass without a
   record, the dead-man check fires. The dead-man check is the only mechanism that can survive a
   fully dead sweep.

8. **A retired process row is kept.** Retired rows are marked `retired: true` with a timestamp
   and cross-reference; they are never deleted. The `process_id` namespace is monotonically
   increasing and non-reusing.

9. **A row's `invariant` is a checkable boolean proposition.** Invariants written in prose that
   cannot be expressed as a boolean query over issue fields and records are not valid registry
   entries. The sweep must be able to assert them without model inference.

10. **The registry is self-governing.** PR-003 (registry maintenance) ensures the registry is
    reviewed on cadence. The PM may not defer registry maintenance indefinitely; the sweep
    escalates overdue reviews.

---

## Consequences

### Benefits

- **`ROUTING` records have a citable authority.** Every `ROUTING.rationale` now has a specific
  row to cite. `PUSHBACK` resolutions are deterministic — they follow the resolution-authority
  column, not power dynamics or context volume.
- **Human escalation is the backstop, not the default.** Class 3 is the only class where the
  human is the *primary* decision-maker. For all other classes, the human is the backstop after
  two facilitation cycles. This keeps the cockpit clear of decisions that personas should own.
- **The PM's triage role is bounded.** The PM owns `unclassified` as a *triage* step, not as a
  resolution. This prevents the PM from accumulating decision authority by letting unclassified
  decisions pile up.
- **Process liveness is machine-checkable.** The sweep can assert every registry invariant as a
  boolean query. "Did PR-001 complete on time?" is a field lookup, not a judgment call.
- **The sweep's own liveness is governed.** PR-002 closes the self-referential gap: if the sweep
  dies, PR-002's invariant fails and the dead-man check surfaces the failure. Previously, a dead
  sweep degraded all guarantees silently.
- **Calibration is a first-class process.** PR-001 ensures every role is explicitly calibrated at
  project start, not assumed to be from persona briefings. `FEEDBACK` records are
  timestamped and queryable.

### Trade-offs

- **Class 2 (state-machine / data contracts) is jointly owned.** Joint ownership adds resolution
  complexity — splits go to PM facilitation immediately rather than to a single adjudicator.
  This is correct: both the Platform Architect and Data Architect have load-bearing stakes in
  contracts; a single-owner ruling would be routinely challenged. The cost is one extra
  facilitation step on the median contested case.
- **The amendment procedure requires human involvement.** Any map change goes to the human via
  `needs_human`. This is a deliberate gate: the ownership map is the governance constitution;
  persona-amendable governance is self-defeating. The cost is latency on map updates.
- **PR-002's dead-man check is an external dependency.** The sweep cannot watchdog itself. The
  dead-man check (cron or GitHub Actions scheduled job) is a second mechanism that must be
  provisioned and maintained. Its runbook is cross-linked from each PR-002 issue instance; its
  own liveness is an operational concern outside the scope of this ADR.
- **`FEEDBACK` is a new record type declared outside ADR-0001.** This means the full
  effective taxonomy requires reading both ADRs. The alternative — amending ADR-0001 — would make
  ADR-0001's revision history noisy with every extension. The cross-reference in both ADRs is the
  discoverability mechanism. If the taxonomy grows large, a separate ADR-0004 taxonomy index is
  the right move.

### Deferred to later

- **Cross-repo ownership map.** This ADR governs decisions within persona-lab. When work spans
  repos, the PMs coordinate via cross-repo issues (per the global working guidance); a
  cross-repo ownership map is a separate ADR in the appropriate coordination repo.
- **Role definitions.** This ADR names roles (`PM`, `Data Architect`, `Platform Architect`,
  `Release Engineer`, `Founder`) but does not define them. Role definitions — capabilities,
  scope, persona bindings — live in the persona briefings, not governance ADRs.
- **Sweep cadence as a tunable value.** PR-002's invariant references `sweep_cadence` as a
  system constant (per ADR-0001). When cadence becomes per-repo-configurable (ADR-0001's deferred
  item), PR-002's invariant window `2×sweep_cadence` follows automatically.
- **ADR-0004 taxonomy index.** If the record taxonomy grows beyond a manageable size for
  cross-ADR cross-referencing, a dedicated taxonomy-index ADR consolidates all record types in
  one place and supersedes the per-ADR declarations.
- **Process registry UI / query tooling.** The registry is currently a table in this ADR and a
  JSON block. A queryable interface (e.g., a jq filter over a generated JSON file) is the right
  next step once the registry has more than ~10 rows.
