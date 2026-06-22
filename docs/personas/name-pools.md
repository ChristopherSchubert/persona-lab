# Persona name pools

Names are a **relationship handle**, layered on a role whose authority/access never changes
(see the design spec, "Per-persona identity, voice & tone"). The human can rename anyone at
any time — these are proposed defaults.

## Rules
- **Platform personas are singletons** — one fixed name each (no pool needed).
- **Repo-tier personas are instantiated per repo**, so each has a **pool of 15**; the bootstrap
  assigns a *distinct* name per repo (your `finances` Developer ≠ your `schubert-family` Developer).
- Each pool is **gender-diverse**.
- **No name is reused across personas** (a name belongs to exactly one persona's pool).
- Names are **plain, clearly human, phonetically distinct** — and **flavored to the role**
  (engineers plain/classic, product more modern, security serious, design stylish, leak-scanner
  utilitarian). All real first names, none fanciful.

## Platform personas (singletons)

| Role | Name |
|---|---|
| Product Manager | Sarah |
| Lead Engineer | Greg |
| Platform Architect | Tom |
| Data Architect | Raj |
| Head of Security | Mike |
| Head of Design | Laura |
| Cost Watch | Dave |

## Repo-tier pools (15 each)

### Developer — plain, classic, unflashy
Ben · Brian · Scott · Doug · Neil · Carl · Wayne · Dennis · Susan · Linda · Carol · Janet · Diane · Nancy · Joan

### Product Analyst — modern, cosmopolitan, a little more interesting
Zoe · Maya · Naomi · Sofia · Aisha · Leah · Ines · Mateo · Diego · Theo · Kai · Nico · Bilal · Arjun · Quinn

### Security Analyst — serious, strong, no-nonsense
Max · Vince · Roman · Ivan · Yusuf · Cole · Reza · Hana · Nadia · Vera · Ingrid · Sloane · Greta · Drew · Reese

### Design Analyst — stylish, creative (still real names)
Esmé · Juno · Lola · Mira · Anouk · Stella · Margot · Luca · Remy · Felix · Jasper · Elio · Otis · Beau · Sasha

### Leak Scanner — plain, utilitarian, workmanlike
Stan · Norm · Gus · Hank · Earl · Roy · Walt · Pam · Bev · Gail · Marge · Donna · Ruth · Edna · Pat
