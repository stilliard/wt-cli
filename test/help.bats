load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- help ---

@test "wt help prints usage" {
  run wt help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "wt --help prints usage" {
  run wt --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "wt -h prints usage" {
  run wt -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
