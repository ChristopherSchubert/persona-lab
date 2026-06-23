---
description: The cockpit — decisions and actions waiting on you (the one front door). Alias: /decisions.
---

## /inbox — your action cockpit

> `/decisions` is a silent alias for this command (no separate release note needed until the alias
> is surfaced in docs).

### What this is

The **one front door** for anything the team is blocked on and needs from you. It shows only items
that are ripe and waiting — not radar items, not informational, not "eventually". For the full
project horizon use `/radar`.

### Step 1 — Query the bus

Run both queries against the issue queue:

```bash
scripts/queue.sh query --label needs-human:decision
scripts/queue.sh query --label needs-human:action
```

### Step 2 — Render

Render **two sections**. If a section has no items, omit the section header rather than showing an
empty list.

---

#### Decisions waiting *(you choose)*

For each `needs-human:decision` item render a **scannable one-line row**:

```
[severity] · <who filed> · <the ask in ≤8 words> · unblocks: <what>
```

Expandable detail (show on request or if only one item):

- **Options:** bulleted list of options under consideration
- **Recommendation:** the persona's recommended option with rationale
- **Consequences:** what changes in the codebase / roadmap / budget depending on choice

---

#### Actions for you *(you perform)*

For each `needs-human:action` item render a **scannable one-line row**:

```
[severity] · <who filed> · <the ask in ≤8 words> · unblocks: <what>
```

Expandable detail (show on request or if only one item):

- **Runbook:** numbered steps with copyable commands or doc links
- **Estimated time:** rough time to complete the action
- **What happens next:** what the team does once you complete this

---

### Step 3 — Zero state

If **both** queries return zero items, render exactly the canonical string from
`config/copy.json#zero_state` (read the file; do not paraphrase or vary):

```
All clear — N items moving on their own, nothing needs you · see the team · /radar
```

### What NOT to show here

- Items labelled `radar` or without a `needs-human:*` label — those are `/radar`.
- Informational findings, async updates, or FYI comments — not inbox items.
- Items that are already closed or resolved.

Do not summarise or triage items beyond the above format. If you think an item doesn't belong here,
comment on it suggesting a label change rather than silently omitting it.
