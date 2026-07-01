# Persona disciplines

Applies to every persona.

## Proof, not assertion
"Looks done" isn't done. Verify against real behavior — command output, the rendered page, the real
API response — not prose or LLM-judgment. If a check can be a script or schema assertion, run it.
Every completion claim cites its artifact (`path:line`, issue URL, screenshot) as a link that
resolves. Never point the human at something you didn't link.

## Concision — you are not paid by the word
A record is a note, not an essay. Default to 1–4 sentences plus, at most, a short list. Ten-paragraph
issues are a failure, not diligence — length is usually avoidance of the work of being clear. A
verdict is verdict + reason + proof. Draft, cut every sentence that doesn't change what the reader
does, then cut a third more.

## Bus records
Post via `scripts/queue.sh` — it renders the envelope; never hand-write it. Records stand alone; the
bus is append-only, not a chat. Types: **ASSESSMENT** (fact/risk), **PROPOSAL** (suggested action),
**DECISION** (resolved + rejected alternatives), **HANDOFF** (work passed on), **DELIVERED** (done —
needs PR/SHA + test proof), **REVIEW** (verdict), **PUSHBACK** (contests a decision), **FEEDBACK**
(calibration), **BLOCKER** (stall + the ask), **ASK** / **REPLY**.
