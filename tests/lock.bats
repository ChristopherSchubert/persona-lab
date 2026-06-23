setup() {
  export PL_TEST_BIN="$(mktemp -d)"; export PATH="$PL_TEST_BIN:$PATH"
  export PL_REF="$(mktemp)"   # PL_REF empty = unlocked
  cat > "$PL_TEST_BIN/gh" <<'SH'
#!/usr/bin/env bash
# Stub for the Git Data API used by lock.sh.
# Dispatch on $1 $2 for mutations (api -X METHOD), then fallback for reads.
# All write calls from lock.sh use -q .sha, so we emit the bare SHA directly.
# Read calls use -q .object.sha; we emit the bare SHA stored in $PL_REF.
# Status calls (no -q, output goes to /dev/null) just exit 0/1.
case "$1 $2" in
  "api -X")
    case "$3" in
      POST)
        case "$4" in
          *git/blobs*)   echo "blobsha";;
          *git/trees*)   echo "treesha";;
          *git/commits*) echo "commitsha111111111111111111111111111111";;
          *git/refs*)
            [ -s "$PL_REF" ] && { echo "HTTP 422 Reference already exists" >&2; exit 1; }
            echo "commitsha111111111111111111111111111111" > "$PL_REF";;
        esac;;
      DELETE)
        : > "$PL_REF";;
      PATCH)
        echo "REFUSED: no updates allowed" >&2; exit 99;;
    esac;;
  "api "*)
    # read or status: $3 is -q (read with filter) or absent (status >/dev/null 2>&1)
    case "$3" in
      -q)
        # gh api <url> -q .object.sha — emit the SHA value directly
        [ -s "$PL_REF" ] && cat "$PL_REF" || { echo "404" >&2; exit 1; };;
      *)
        # gh api <url> >/dev/null 2>&1 (status check)
        [ -s "$PL_REF" ] && exit 0 || exit 1;;
    esac;;
esac
SH
  chmod +x "$PL_TEST_BIN/gh"
}
teardown() { rm -rf "$PL_TEST_BIN" "$PL_REF"; }

@test "lock claim: returns the fence (the lock commit SHA)" {
  run scripts/lock.sh claim --repo finances --holder Ben
  [ "$status" -eq 0 ]; [[ "$output" == "commitsha111111111111111111111111111111" ]]
}
@test "lock claim: second claim is refused (held), no force/update attempted" {
  scripts/lock.sh claim --repo finances --holder Ben >/dev/null
  run scripts/lock.sh claim --repo finances --holder Alex
  [ "$status" -ne 0 ]
}
@test "verify-fence: matches while held, fails after a steal" {
  fence="$(scripts/lock.sh claim --repo finances --holder Ben)"
  run scripts/lock.sh verify-fence --repo finances --fence "$fence"
  [ "$status" -eq 0 ]
  echo "different2222222222222222222222222222222" > "$PL_REF"
  run scripts/lock.sh verify-fence --repo finances --fence "$fence"
  [ "$status" -ne 0 ]
}
@test "lock release then re-claim succeeds" {
  scripts/lock.sh claim --repo finances --holder Ben >/dev/null
  scripts/lock.sh release --repo finances --holder Ben
  run scripts/lock.sh claim --repo finances --holder Alex
  [ "$status" -eq 0 ]
}
