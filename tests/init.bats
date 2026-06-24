setup() { export PL_CONFIG_DIR="$(mktemp -d)"; }
teardown() { rm -rf "$PL_CONFIG_DIR"; }
@test "init: writes a yq-valid single-repo manifest with conservative oversight" {
  run scripts/init.sh --repo finances --owner Chris --personas "developer:writes,product-analyst:owns"
  [ "$status" -eq 0 ]
  mf="$PL_CONFIG_DIR/manifest.yml"; [ -f "$mf" ]
  [ "$(yq -r .grain "$mf")" = "single" ]
  [ "$(yq -r .repo "$mf")" = "finances" ]
  [ "$(yq -r .oversight.autonomy "$mf")" = "conservative" ]
  [ "$(yq -r '.engagement.developer.capacity' "$mf")" = "writes" ]
}
@test "init: refuses to clobber an existing manifest without --force" {
  scripts/init.sh --repo a --owner x --personas "developer:writes" >/dev/null
  run scripts/init.sh --repo b --owner y --personas "developer:writes"
  [ "$status" -ne 0 ]
}
@test "init: rejects an unknown capacity" {
  run scripts/init.sh --repo r --owner o --personas "developer:wrtes"
  [ "$status" -ne 0 ]
}
