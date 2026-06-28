@test "assert-access: developer(writes) maps to the writes tool set" {
  run scripts/assert-access.sh tools-for writes
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'Write'
  echo "$output" | grep -qF 'Bash'
}
@test "assert-access: reader capacity excludes Write/Edit" {
  run scripts/assert-access.sh tools-for reads
  [ "$status" -eq 0 ]
  if echo "$output" | grep -qF 'Write'; then false; fi
  if echo "$output" | grep -qF 'Edit';  then false; fi
}
@test "assert-access: unknown capacity fails loudly" {
  run scripts/assert-access.sh tools-for boguscap
  [ "$status" -ne 0 ]
}
