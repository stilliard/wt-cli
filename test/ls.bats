load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_ls ---

@test "wt ls lists worktrees" {
  run _wt_ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO "* ]]
  [[ "$output" == *"feature"* ]]
  [[ "$output" == *"other"* ]]
}

@test "wt with no args lists worktrees" {
  run wt
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt list alias works" {
  run wt list
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt ls alias works" {
  run wt ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt ls errors on unknown flag" {
  run wt ls --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "wt ls --branch prints just branch names, one per line" {
  run _wt_ls --branch
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == "master" || "${lines[0]}" == "main" ]]
  [ "${lines[1]}" = "feature" ]
  [ "${lines[2]}" = "other" ]
}

@test "wt ls --path prints just paths, one per line" {
  run _wt_ls --path
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "$TEST_REPO" ]
  [ "${lines[1]}" = "$TEST_REPO-feature" ]
  [ "${lines[2]}" = "$TEST_REPO-other" ]
}

@test "wt ls --branch and --path together error" {
  run _wt_ls --branch --path
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "wt ls --claude with --branch errors instead of ignoring --claude" {
  run _wt_ls --claude --branch
  [ "$status" -ne 0 ]
  [[ "$output" == *"--claude"* ]]
}

@test "wt ls --claude with --path errors instead of ignoring --claude" {
  run _wt_ls --path --claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"--claude"* ]]
}
