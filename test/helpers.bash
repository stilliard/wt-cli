# shared setup/teardown for all test files.
#
# usage, from a .bats file:
#   load helpers            # test/*.bats
#   load ../helpers          # test/claude/*.bats
#
#   setup()    { wt_common_setup; }
#   teardown() { wt_common_teardown; }

wt_common_setup() {
  # create a temp repo and two worktrees
  TEST_REPO=$(mktemp -d)
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "init"

  git worktree add -q "$TEST_REPO-feature" -b feature
  git worktree add -q "$TEST_REPO-other" -b other

  # locate wt.sh by walking up from the test file's directory, so tests work
  # at any nesting depth and don't require a git checkout
  local dir="$BATS_TEST_DIRNAME"
  while [ ! -f "$dir/wt.sh" ] && [ "$dir" != "/" ]; do
    dir=$(dirname "$dir")
  done
  WT_SH="$dir/wt.sh"
  source "$WT_SH"
}

wt_common_teardown() {
  rm -rf "$TEST_REPO" "$TEST_REPO-feature" "$TEST_REPO-other"
}
