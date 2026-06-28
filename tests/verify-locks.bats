# verify-locks.bats — audit of the access model in agent `tools:` frontmatter.
# Three tiers: developer (Write+Edit+Bash), doc-writers (Write+Edit, no Bash), everyone else (neither).

setup() {
  export PL_DOC_WRITERS="$(mktemp)"; printf 'technical-writer\n' > "$PL_DOC_WRITERS"  # roster: one doc-writer
}
teardown() { rm -f "$PL_DOC_WRITERS"; }

dev_ok() { printf -- '---\ntools: Read, Edit, Write, Bash, Grep, Glob\n---\n' > "$1/developer.md"; }

@test "verify-locks: passes — developer (Write+Edit+Bash) + a pure reader" {
  d="$(mktemp -d)"; dev_ok "$d"
  printf -- '---\ntools: Read, Grep, Glob\n---\n' > "$d/product-analyst.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -eq 0 ]; rm -rf "$d"
}

@test "verify-locks: passes — a doc-writer with Write+Edit and NO Bash" {
  d="$(mktemp -d)"; dev_ok "$d"
  printf -- '---\ntools: Read, Edit, Write, Grep, Glob\n---\n' > "$d/technical-writer.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -eq 0 ]; rm -rf "$d"
}

@test "verify-locks: fails — developer LACKS Write (vacuous pass)" {
  d="$(mktemp -d)"; printf -- '---\ntools: Read, Grep, Glob\n---\n' > "$d/developer.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -ne 0 ]; rm -rf "$d"
}

@test "verify-locks: fails — developer LACKS Bash (code-writer lock degraded)" {
  d="$(mktemp -d)"; printf -- '---\ntools: Read, Edit, Write, Grep, Glob\n---\n' > "$d/developer.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -ne 0 ]; rm -rf "$d"
}

@test "verify-locks: fails — a NON-doc-writer reader HAS Write" {
  d="$(mktemp -d)"; dev_ok "$d"
  printf -- '---\ntools: Read, Edit, Write, Grep, Glob\n---\n' > "$d/product-analyst.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -ne 0 ]; rm -rf "$d"
}

@test "verify-locks: fails — a doc-writer has Bash (only the code writer may)" {
  d="$(mktemp -d)"; dev_ok "$d"
  printf -- '---\ntools: Read, Edit, Write, Bash, Grep, Glob\n---\n' > "$d/technical-writer.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -ne 0 ]; rm -rf "$d"
}

@test "verify-locks: fails — a doc-writer is MISSING Write" {
  d="$(mktemp -d)"; dev_ok "$d"
  printf -- '---\ntools: Read, Grep, Glob\n---\n' > "$d/technical-writer.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -ne 0 ]; rm -rf "$d"
}
