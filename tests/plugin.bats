#!/usr/bin/env bats
# tests/plugin.bats — Issue #50: plugin bootstrap-path and manifest correctness

# Resolve repo root from this test file's location
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# ---------------------------------------------------------------------------
# A) No bare scripts/…  invocations in bundled command files
#    Every script reference that runs a bundled script must use
#    "${CLAUDE_PLUGIN_ROOT}"/scripts/…
# ---------------------------------------------------------------------------

# check_bare_scripts FILE
# Exits 1 if any code-block line in FILE begins with 'scripts/' without the
# ${CLAUDE_PLUGIN_ROOT} prefix.  Prose mentions (e.g. backtick-quoted names in
# body text) are not flagged — only lines that would literally be executed.
check_bare_scripts() {
  local file="$1"
  # Lines that start (ignoring leading whitespace) with `scripts/` are bare
  # invocations.  Lines starting with `"${CLAUDE_PLUGIN_ROOT}"` are correct.
  # We exclude lines that are clearly prose: they contain backtick-only
  # references (like `` `scripts/foo.sh` ``) that are surrounded by other text.
  # The reliable signal is: does the line (after trimming) START with scripts/?
  local bare_lines
  bare_lines=$(grep -n 'scripts/[^ ]*\.sh' "$file" \
    | grep -v '"\${CLAUDE_PLUGIN_ROOT}"' \
    | grep -E '^[0-9]+:[[:space:]]*scripts/' ) || true

  if [ -n "$bare_lines" ]; then
    echo "Found bare scripts/*.sh invocation lines (should use \"\${CLAUDE_PLUGIN_ROOT}\"/scripts/):"
    echo "$bare_lines"
    return 1
  fi
  return 0
}

@test "persona-init.md: no bare scripts/*.sh invocations" {
  local file="$REPO_ROOT/commands/persona-init.md"
  [ -f "$file" ] || fail "missing $file"
  check_bare_scripts "$file"
}

@test "persona.md: no bare scripts/*.sh invocations" {
  local file="$REPO_ROOT/commands/persona.md"
  [ -f "$file" ] || fail "missing $file"
  check_bare_scripts "$file"
}

@test "inbox.md: no bare scripts/*.sh invocations" {
  local file="$REPO_ROOT/commands/inbox.md"
  [ -f "$file" ] || fail "missing $file"
  check_bare_scripts "$file"
}

# ---------------------------------------------------------------------------
# B) plugin.json manifest correctness
# ---------------------------------------------------------------------------

@test "plugin.json is valid JSON" {
  local file="$REPO_ROOT/.claude-plugin/plugin.json"
  [ -f "$file" ] || fail "missing $file"
  jq empty "$file"
}

@test "plugin.json has no 'skills' key" {
  local file="$REPO_ROOT/.claude-plugin/plugin.json"
  local has_skills
  has_skills=$(jq 'has("skills")' "$file")
  [ "$has_skills" = "false" ] || {
    echo "plugin.json still contains 'skills' key (directory does not exist — remove the key)"
    return 1
  }
}

@test "plugin.json has 'repository' field" {
  local file="$REPO_ROOT/.claude-plugin/plugin.json"
  local has_repo
  has_repo=$(jq 'has("repository")' "$file")
  [ "$has_repo" = "true" ] || {
    echo "plugin.json is missing 'repository' field"
    return 1
  }
}

@test "plugin.json 'repository' is the canonical GitHub URL" {
  local file="$REPO_ROOT/.claude-plugin/plugin.json"
  local repo_val
  repo_val=$(jq -r '.repository' "$file")
  [ "$repo_val" = "https://github.com/ChristopherSchubert/persona-lab" ] || {
    echo "Expected repository 'https://github.com/ChristopherSchubert/persona-lab', got '$repo_val'"
    return 1
  }
}

@test "skills/ directory does not exist (no dangling reference)" {
  local skills_dir="$REPO_ROOT/skills"
  if [ -d "$skills_dir" ]; then
    echo "skills/ directory exists — either add it to the plugin or remove it from plugin.json"
    return 1
  fi
}
