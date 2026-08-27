load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_cd ---

@test "wt <name> navigates to worktree" {
  _wt_cd feature
  [ "$PWD" = "$TEST_REPO-feature" ]
}

@test "wt cd <name> navigates to worktree" {
  wt cd other
  [ "$PWD" = "$TEST_REPO-other" ]
}

@test "wt <name> returns error for no match" {
  run _wt_cd nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
}

@test "wt ~ goes to the repo root" {
  cd "$TEST_REPO-feature"
  _wt_cd "~"
  [ "$PWD" = "$TEST_REPO" ]
}

@test "wt ~ works after the shell has expanded it to \$HOME" {
  cd "$TEST_REPO-feature"
  _wt_cd "$HOME"
  [ "$PWD" = "$TEST_REPO" ]
}

@test "wt root goes to the repo root" {
  cd "$TEST_REPO-other"
  wt root
  [ "$PWD" = "$TEST_REPO" ]
}

@test "a worktree named root still wins over the repo root" {
  git -C "$TEST_REPO" worktree add -q "$TEST_REPO-root" -b root
  cd "$TEST_REPO-feature"
  _wt_cd root
  [ "$PWD" = "$TEST_REPO-root" ]
  cd "$TEST_REPO"
  git worktree remove "$TEST_REPO-root"
}

@test "wt ~ outside a repo fails rather than going home" {
  local outside; outside=$(mktemp -d)
  cd "$outside"
  run _wt_cd "~"
  [ "$status" -ne 0 ]
  cd "$TEST_REPO"
  rm -rf "$outside"
}

@test "a worktree named code is still reachable via wt cd" {
  git -C "$TEST_REPO" worktree add -q "$TEST_REPO-code" -b code
  cd "$TEST_REPO-feature"
  wt cd code
  [ "$PWD" = "$TEST_REPO-code" ]
  cd "$TEST_REPO"
  git worktree remove "$TEST_REPO-code"
}
