@test "assert-access: developer(writes) maps to the writes tool set" {
  run scripts/assert-access.sh tools-for writes
  [ "$status" -eq 0 ]; [[ "$output" == *"Write"* && "$output" == *"Bash"* ]]
}
@test "assert-access: reader capacity excludes Write/Edit" {
  run scripts/assert-access.sh tools-for reads
  [ "$status" -eq 0 ]; [[ "$output" != *"Write"* && "$output" != *"Edit"* ]]
}
