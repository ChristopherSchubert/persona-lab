---
description: Bootstrap persona-lab in this repo — interview, generate config, go live.
---

## Prerequisites

This command requires the following tools to be installed:

- `yq` — YAML parser (brew install yq); required for manifest reads in `build-agents.sh`
- `jq` — JSON processor (brew install jq); required for capacity validation in `init.sh`
- `gh` — GitHub CLI (brew install gh); required for repo detection and label provisioning
- `bats` — Bash test framework (brew install bats-core); required for running `bats tests/`

---

## /persona-init — bootstrap interview

Run the interview **one question at a time**. Do not dump all questions at once. Wait for each
answer before asking the next.

---

### Phase 2 scope (state, do not ask)

Grain is **single-repo** for this release (Phase 3 adds platform-level personas). Tell the human
this upfront so they understand the scope.

---

### Interview sequence

**Question 1 — owner**

Ask: "What is your name? (This becomes the `owner` in the manifest.)"

**Question 2 — repo**

Detect the default by running:

```bash
gh repo view --json name -q .name
```

Ask: "Which repo are we bootstrapping? (default: <detected name>)" Accept Enter to take the
default.

**Question 3 — disciplines in scope**

Present the menu clearly. Tell the human the **default minimal set is `developer` +
`product-analyst`** and ask which (if any) to add.

Available disciplines and their capacities (capacity is fixed — not a menu choice):

| slug | capacity | tier |
|------|----------|------|
| `developer` | `writes` | repo |
| `product-analyst` | `owns` | repo |
| `security-analyst` | `audits` | repo |
| `design-analyst` | `audits` | repo |
| `product-manager` | `owns` | platform singleton |
| `lead-engineer` | `audits` | platform singleton |
| `platform-architect` | `owns` | platform singleton |
| `data-architect` | `owns` | platform singleton |
| `head-of-security` | `owns` | platform singleton |
| `head-of-design` | `owns` | platform singleton |
| `head-of-finops` | `owns` | platform singleton |

Wait for the human's answer. Build the final slug:capacity list from their selection.

**Question 4 — trigger mode**

Ask: "How should personas be triggered? Options: summon-only / on-demand / scheduled / event.
(default: summon-only in Phase 2)"

Accept the default unless the human overrides.

**Question 5 — daily budget ceiling**

Ask: "What is your daily budget ceiling (token count or dollar amount, e.g. `$2.00` or `500000
tokens`)? This is recorded now and enforced in Phase 4."

Record the answer verbatim in the summary. Do not skip this question.

---

### Governance invariants (state, do NOT ask)

Tell the human — not as options, but as statements of fact:

> **Autonomy:** conservative by default — all personas escalate rather than self-authorise; auto-mode
> is **not** enabled at install and requires an explicit governance change, not a menu toggle.
>
> **Visibility:** minimal — no ambient telemetry or broadcasting beyond what the run-log captures
> per invocation.
>
> These are governance invariants, not configuration choices. They are baked into every manifest
> this command writes.

---

### Propose names

For each in-scope persona slug, run:

```bash
scripts/assign-names.sh <slug> <repo>
```

Show the proposed name for each persona. Example output:

> - developer → **Maya**
> - product-analyst → **Ben**

Ask: "Any names you'd like to change? (Press Enter to accept all.)" Accept overrides. Use the
(possibly overridden) names only for display; slugs are the canonical identifiers in the manifest.

---

### Generate and provision

Run the scripts in this order. Do not skip any step.

**Step 1 — write the manifest**

Build the `--personas` value as a comma-separated `slug:capacity` string, e.g.:
`"developer:writes,product-analyst:owns"`

Check whether `.claude/persona-lab/manifest.yml` already exists:

```bash
test -f .claude/persona-lab/manifest.yml && echo exists || echo absent
```

- If **absent**: run normally.
- If **present**: warn the human and ask for explicit confirmation before adding `--force`. If
  they decline, stop here.

```bash
scripts/init.sh --repo <repo> --owner <owner> --personas "<slug:cap,...>"
# add --force only if the human confirmed overwriting an existing manifest
```

**Step 2 — provision labels**

```bash
scripts/setup-labels.sh
```

**Step 3 — generate agent files**

```bash
scripts/build-agents.sh
```

---

### Verify the access-lock invariant

Before declaring success, verify that Write/Edit access is confined to the developer agent only.

Run:

```bash
scripts/verify-locks.sh
```

This script asserts both:
- **Positive**: `agents/developer.md` MUST have both `Write` and `Edit` in its `tools:` line (catches silent degradation where the developer loses write access).
- **Negative**: no other agent may have `Write` or `Edit` in its `tools:` line.

If `verify-locks.sh` exits non-zero, **STOP immediately** — do not proceed. Report the error message from the script verbatim and investigate `scripts/build-agents.sh` and the manifest capacities before using any persona.

Note: valid capacity values are exactly `writes`, `owns`, `audits`, `advises`, `reads`.

---

### Report ready

If the invariant check passes, report:

> persona-lab is live in **<repo>** — <N> personas (<name> as <slug>, …).
>
> Try `/persona <name>` (summon) or `/inbox` (cockpit).
>
> Note: re-running `/persona-init` is safe to attempt; `init.sh` refuses to clobber the manifest
> without explicit confirmation and `--force`.
