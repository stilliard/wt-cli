load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_prune ---

@test "wt prune runs without error" {
  run wt prune
  [ "$status" -eq 0 ]
}
