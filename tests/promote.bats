setup() {
  export PL_CONFIG_DIR="$(mktemp -d)"
  scripts/init.sh --repo finances --owner Chris --personas "developer:writes" >/dev/null
}
teardown() { rm -rf "$PL_CONFIG_DIR"; }

@test "promote: single -> platform adds repos list" {
  run scripts/promote.sh --add-repo travel
  [ "$status" -eq 0 ]
  mf="$PL_CONFIG_DIR/manifest.yml"
  [ "$(yq -r .grain "$mf")" = "platform" ]
  [ "$(yq -r '.repos | length' "$mf")" = "2" ]
  yq -e '.repos | contains(["finances","travel"])' "$mf"
}

@test "promote: appending an existing repo is idempotent" {
  scripts/promote.sh --add-repo travel >/dev/null
  scripts/promote.sh --add-repo travel >/dev/null
  [ "$(yq -r '.repos | length' "$PL_CONFIG_DIR/manifest.yml")" = "2" ]
}

@test "promote: platform -> appends new repo to existing list" {
  scripts/promote.sh --add-repo travel >/dev/null
  run scripts/promote.sh --add-repo savings
  [ "$status" -eq 0 ]
  mf="$PL_CONFIG_DIR/manifest.yml"
  [ "$(yq -r .grain "$mf")" = "platform" ]
  [ "$(yq -r '.repos | length' "$mf")" = "3" ]
  yq -e '.repos | contains(["finances","travel","savings"])' "$mf"
}

@test "promote: invalid repo name fails" {
  run scripts/promote.sh --add-repo "../evil"
  [ "$status" -ne 0 ]
}

@test "promote: no manifest fails" {
  rm "$PL_CONFIG_DIR/manifest.yml"
  run scripts/promote.sh --add-repo travel
  [ "$status" -ne 0 ]
}

@test "promote: result is yq-valid YAML" {
  scripts/promote.sh --add-repo travel >/dev/null
  yq . "$PL_CONFIG_DIR/manifest.yml" >/dev/null
}
