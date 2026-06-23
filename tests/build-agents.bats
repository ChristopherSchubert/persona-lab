@test "build-agents: emits one agent per briefing with disciplines concatenated + tools frontmatter" {
  export PL_OUT="$(mktemp -d)"
  run scripts/build-agents.sh --out "$PL_OUT"
  [ "$status" -eq 0 ]
  [ -f "$PL_OUT/developer.md" ]
  grep -q "tools:" "$PL_OUT/developer.md"
  grep -q "Verification hierarchy" "$PL_OUT/developer.md"
}
