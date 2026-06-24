@test "verify-locks: passes when only developer has Write/Edit" {
  d="$(mktemp -d)"; printf -- '---\ntools: Read, Edit, Write, Bash, Grep, Glob\n---\n' > "$d/developer.md"
  printf -- '---\ntools: Read, Grep, Glob\n---\n' > "$d/product-analyst.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -eq 0 ]; rm -rf "$d"
}
@test "verify-locks: fails when developer LACKS Write (vacuous pass)" {
  d="$(mktemp -d)"; printf -- '---\ntools: Read, Grep, Glob\n---\n' > "$d/developer.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -ne 0 ]; rm -rf "$d"
}
@test "verify-locks: fails when a reader HAS Write" {
  d="$(mktemp -d)"; printf -- '---\ntools: Read, Edit, Write, Bash, Grep, Glob\n---\n' > "$d/developer.md"
  printf -- '---\ntools: Read, Edit, Write, Grep, Glob\n---\n' > "$d/product-analyst.md"
  run scripts/verify-locks.sh --dir "$d"; [ "$status" -ne 0 ]; rm -rf "$d"
}
