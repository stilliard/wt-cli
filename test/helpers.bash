# shared setup/teardown for all test files.
#
# usage, from a .bats file:
#   load helpers            # test/*.bats
#   load ../helpers          # test/claude/*.bats
#
#   setup()    { wt_common_setup; }
#   teardown() { wt_common_teardown; }

wt_common_setup() {
  # create a temp bare repo and two worktrees
  TEST_REPO=$(mktemp -d)
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "init"

  git worktree add -q "$TEST_REPO-feature" -b feature
  git worktree add -q "$TEST_REPO-other" -b other

  local repo_root; repo_root=$(cd "$BATS_TEST_DIRNAME" && git rev-parse --show-toplevel)
  source "$repo_root/wt.sh"
}

wt_common_teardown() {
  rm -rf "$TEST_REPO" "$TEST_REPO-feature" "$TEST_REPO-other"
}
