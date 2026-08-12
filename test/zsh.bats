load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# zsh ties the `path` array to $PATH, so a `local path` (or a bare
# `read -r path`) inside a function empties PATH for that function and
# everything it calls - git/awk stop resolving mid-run. bash ignores this
# entirely, so the behavioural test has to run under a real zsh.

@test "wt merged --rm works under zsh (PATH not clobbered by a 'path' local)" {
  command -v zsh >/dev/null || skip "zsh not installed"
  git -C "$TEST_REPO" merge -q feature

  run zsh -c "cd '$TEST_REPO'; source '$WT_SH'; wt merged --rm -y"
  [ "$status" -eq 0 ]
  [[ "$output" != *"git: command not found"* ]]
  [[ "$output" != *"command not found: git"* ]]
  [[ "$output" != *"no worktree matching"* ]]
  [ ! -d "$TEST_REPO-feature" ]
}

# static guard: catches new occurrences in any function, including ones with
# no zsh test coverage. WT_PATH (the hook env var) is not a special name.
@test "no shell variable is named 'path'" {
  run grep -nE '(^|[[:space:];])(local|typeset)[^=]*[[:space:]]path([[:space:]=]|$)|read([[:space:]]+-[^[:space:]]+)*[[:space:]]+path([[:space:]]|$)' "$WT_SH"
  [ "$status" -ne 0 ]
}
