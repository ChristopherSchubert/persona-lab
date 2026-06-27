# Persona roster

Each role has **exactly one person** — a fixed name, the same across every repo. A name is a
**relationship handle**, layered on a role whose authority/access never changes (see the design spec,
"Per-persona identity, voice & tone"). The human can rename anyone at any time — these are the
proposed defaults.

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

Diversity of the group as a whole: 8 women, 8 men, 1 gender-neutral (Morgan); spanning Western,
South Asian (Raj, Priya), Latino (Carmen, Lola, Mateo), Slavic / Eastern-European (Pavel),
MENA (Aisha), and East Asian (Hana).

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
