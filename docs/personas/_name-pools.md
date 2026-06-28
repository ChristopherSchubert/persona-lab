# Persona roster

Each role has **exactly one person** — a fixed name, the same across every repo. Names are **fixed**,
not renamed at runtime. A name is a stable identity layered on a role whose authority and access are
set by the role, not the name.

## Rules
- **One person per role** — one fixed name each, identical across all repos (no per-repo pools).
- **No name is reused** across roles.
- The roster is **gender- and culturally diverse as a whole**.
- Names are **plain, clearly human, phonetically distinct**, and **flavored to the role**
  (engineers plain/classic, product modern, security serious, design stylish). All real first names.

## Roster

| Role | Name |
|---|---|
| Product Manager | Sarah |
| Lead Engineer | Greg |
| Platform Architect | Tom |
| Enterprise Architect | Eleanor |
| Data Architect | Raj |
| Head of Security | Mike |
| Head of QA | Priya |
| Head of Design | Laura |
| FinOps | Dave |
| Marketing | Carmen |
| Developer | Doug |
| Product Analyst | Aisha |
| Security Analyst | Hana |
| Design Analyst | Lola |
| QA Analyst | Pavel |
| Technical Writer | Morgan |
| Release Engineer | Mateo |
| Delivery Manager | Remy |
| Reliability Engineer | Kai |
| Accessibility Analyst | Nadia |
| Privacy Analyst | Vera |

## Avatars

Each name has a **per-individual pixel-art avatar** under `assets/avatars/<name>/` (lowercase, ASCII —
Esmé → `esme`). One avatar per name (names are unique across the roster). Faces are flavored like the
names (engineers plain, product modern, security serious, design stylish).

- **PNG, not SVG** — GitHub renders PNG in issue comments; raw SVG won't display.
- Square, pixel-art, ~64–128px native so it stays crisp at 16–20px.
- Referenced by **absolute URL** in the comment-envelope header (beside the AI flag), the dashboard
  roster, and the cockpit.
- An avatar is a **receipt, not a mask** — show it next to the persona's track record (e.g. "41 closed,
  0 reverted") so the face earns trust rather than just decorating.
