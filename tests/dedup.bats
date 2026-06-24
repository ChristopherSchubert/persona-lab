setup() { export PL_LEDGER="$(mktemp -d)/fingerprints"; mkdir -p "$PL_LEDGER"; }

@test "dedup: first sighting is new, returns the fingerprint" {
  run scripts/dedup.sh check --persona Ben --rule clock-skew --path auth/session.ts --snippet "iat future"
  [ "$status" -eq 0 ]; [[ "$output" == new:* ]]
}
@test "dedup: second identical sighting is a duplicate of the same fingerprint" {
  scripts/dedup.sh check --persona Ben --rule clock-skew --path auth/session.ts --snippet "iat future" >/dev/null
  run scripts/dedup.sh check --persona Ben --rule clock-skew --path auth/session.ts --snippet "iat future"
  [ "$status" -eq 0 ]; [[ "$output" == dup:* ]]
}
