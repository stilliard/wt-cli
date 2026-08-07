load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# wt.sh is sourced into the user's interactive shell, which for many users is
# zsh. bats runs under bash, so bash-only tests can't see zsh-specific
# breakage - most notably that zsh ties the `path` array to `PATH`, so a
# `local path` blanks PATH for the rest of the function.

@test "no shell local is named 'path' (zsh ties it to PATH)" {
  local dir="$BATS_TEST_DIRNAME"
  while [ ! -f "$dir/wt.sh" ] && [ "$dir" != "/" ]; do dir=$(dirname "$dir"); done
  run grep -nE "^[[:space:]]*local .*(^|[[:space:]])path([=[:space:]]|$)" "$dir/wt.sh"
  [ "$status" -ne 0 ]
}

@test "wt merged runs under zsh without losing PATH" {
  command -v zsh >/dev/null || skip "zsh not installed"
  local dir="$BATS_TEST_DIRNAME"
  while [ ! -f "$dir/wt.sh" ] && [ "$dir" != "/" ]; do dir=$(dirname "$dir"); done

  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  git -C "$TEST_REPO" merge -q feature

  run zsh -c "source '$dir/wt.sh' 2>/dev/null; cd '$TEST_REPO'; wt merged '$base'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[feature]"* ]]
  [[ "$output" != *"command not found"* ]]
}
