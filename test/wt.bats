setup() {
  # create a temp bare repo and two worktrees
  TEST_REPO=$(mktemp -d)
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "init"

  git worktree add -q "$TEST_REPO-feature" -b feature
  git worktree add -q "$TEST_REPO-other" -b other

  source "$BATS_TEST_DIRNAME/../wt.sh"
}

teardown() {
  rm -rf "$TEST_REPO" "$TEST_REPO-feature" "$TEST_REPO-other"
}

# --- _wt_resolve ---

@test "_wt_resolve finds worktree by branch name" {
  result=$(_wt_resolve feature)
  [ "$result" = "$TEST_REPO-feature" ]
}

@test "_wt_resolve finds worktree by directory basename" {
  result=$(_wt_resolve "$(basename "$TEST_REPO-other")")
  [ "$result" = "$TEST_REPO-other" ]
}

@test "_wt_resolve returns empty string for no match" {
  result=$(_wt_resolve nonexistent)
  [ -z "$result" ]
}

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

# --- _wt_mk ---

@test "wt mk creates worktree as repo sibling" {
  local branch="my-feature"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt mk "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt add alias creates worktree" {
  local branch="via-add"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt add "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt mk replaces slashes in branch name with dashes" {
  local branch="type/my-thing"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-type-my-thing"
  wt mk "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt mk accepts explicit path" {
  local dest="$TEST_REPO-explicit"
  wt mk explicit-path "$dest"
  [ -d "$dest" ]
  git worktree remove "$dest"
  rm -rf "$dest"
}

# --- _wt_rm ---

@test "wt rm removes a worktree" {
  run wt rm feature
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-feature" ]
}

@test "wt remove alias removes a worktree" {
  run wt remove other
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-other" ]
}

@test "wt rm returns error for no match" {
  run wt rm nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
}

# --- _wt_prune ---

@test "wt prune runs without error" {
  run wt prune
  [ "$status" -eq 0 ]
}

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

# --- hooks ---

@test "post-mk hook is called with WT_BRANCH and WT_PATH" {
  local branch="hook-test"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH path=$WT_PATH" > /tmp/wt-hook-out' > "$TEST_REPO/.wt-hooks/post-mk"
  chmod +x "$TEST_REPO/.wt-hooks/post-mk"
  wt mk "$branch"
  local out; out=$(cat /tmp/wt-hook-out); rm -f /tmp/wt-hook-out
  git worktree remove "$expected"
  [[ "$out" == "branch=$branch path=$expected" ]]
}

@test "post-rm hook is called with WT_BRANCH and WT_PATH" {
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH path=$WT_PATH" > /tmp/wt-hook-out' > "$TEST_REPO/.wt-hooks/post-rm"
  chmod +x "$TEST_REPO/.wt-hooks/post-rm"
  wt rm feature
  local out; out=$(cat /tmp/wt-hook-out); rm -f /tmp/wt-hook-out
  [[ "$out" == "branch=feature path=$TEST_REPO-feature" ]]
}

@test "hooks are skipped when .wt-hooks dir does not exist" {
  local branch="no-hook"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  run wt mk "$branch"
  [ "$status" -eq 0 ]
  git worktree remove "$expected"
}

@test "pre-mk hook failure aborts worktree creation" {
  local branch="pre-mk-abort"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\nexit 1' > "$TEST_REPO/.wt-hooks/pre-mk"
  chmod +x "$TEST_REPO/.wt-hooks/pre-mk"
  run wt mk "$branch"
  [ "$status" -ne 0 ]
  [ ! -d "$expected" ]
}

@test "pre-rm hook failure aborts worktree removal" {
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\nexit 1' > "$TEST_REPO/.wt-hooks/pre-rm"
  chmod +x "$TEST_REPO/.wt-hooks/pre-rm"
  run wt rm feature
  [ "$status" -ne 0 ]
  [ -d "$TEST_REPO-feature" ]
}

# --- dispatcher aliases ---

@test "wt ls alias works" {
  run wt ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}
