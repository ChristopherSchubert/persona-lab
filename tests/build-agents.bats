@test "build-agents: emits one agent per briefing with disciplines concatenated + tools frontmatter" {
  export PL_OUT="$(mktemp -d)"
  run scripts/build-agents.sh --out "$PL_OUT"
  [ "$status" -eq 0 ]
  [ -f "$PL_OUT/developer.md" ]
  grep -q "tools:" "$PL_OUT/developer.md"
  grep -q "Verification hierarchy" "$PL_OUT/developer.md"
}

@test "build-agents: sparse manifest builds only rostered personas" {
  export PL_CONFIG_DIR="$(mktemp -d)"; export PL_OUT="$(mktemp -d)"
  scripts/init.sh --repo r --owner o --personas "developer:writes,product-analyst:owns" >/dev/null
  run scripts/build-agents.sh --out "$PL_OUT"
  [ "$status" -eq 0 ]
  [ -f "$PL_OUT/developer.md" ] && [ -f "$PL_OUT/product-analyst.md" ]
  [ ! -f "$PL_OUT/head-of-security.md" ]   # not in roster -> skipped, not built
  rm -rf "$PL_CONFIG_DIR" "$PL_OUT"
}
