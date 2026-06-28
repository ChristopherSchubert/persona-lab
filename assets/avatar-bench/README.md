# Avatar bench — reserve pool

Pre-made pixel-art avatars recovered from earlier name-pool work, kept on the shelf so
adding a persona never blocks on new art. These are **not** active roster members —
nothing in the system references them until one is promoted.

**To promote one to a persona:** move `avatar-bench/<name>/` → `avatars/<name>/`, add the
role + name to the roster (`docs/personas/_name-pools.md`), and run `scripts/build-agents.sh`.
Identity is conveyed by the name + the image, the same as every other persona — no race/age
metadata is recorded.
