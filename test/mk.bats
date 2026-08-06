load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_mk ---

@test "wt mk creates worktree as repo sibling" {
  local branch="my-feature"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt mk "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt mk cds into new worktree" {
  local branch="cd-test"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt mk "$branch"
  [ "$PWD" = "$expected" ]
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

@test "wt mk --base creates branch from specified base" {
  local branch="based-branch"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt mk --base feature "$branch"
  local base_commit; base_commit=$(git -C "$TEST_REPO-feature" rev-parse HEAD)
  local new_commit; new_commit=$(git -C "$expected" rev-parse HEAD)
  [ "$new_commit" = "$base_commit" ]
  git worktree remove "$expected"
}

@test "wt mk errors on unknown flag" {
  run wt mk --bogus value branch
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
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

# --- .worktreeinclude ---

@test "wt mk copies gitignored files listed in .worktreeinclude" {
  local branch="wti-copy"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  echo "*.env" > "$TEST_REPO/.gitignore"
  echo "SECRET=1" > "$TEST_REPO/prod.env"
  echo "*.env" > "$TEST_REPO/.worktreeinclude"
  wt mk "$branch"
  local ok=1
  [ "$(cat "$expected/prod.env" 2>/dev/null)" = "SECRET=1" ] || ok=0
  cd "$TEST_REPO"
  git worktree remove --force "$expected"
  rm -rf "$expected"
  [ "$ok" -eq 1 ]
}

@test "wt mk copies gitignored files with special characters in their names" {
  local branch="wti-special"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  echo "*.env" > "$TEST_REPO/.gitignore"
  printf 'VAL=1' > "$TEST_REPO/wéird name.env"
  echo "*.env" > "$TEST_REPO/.worktreeinclude"
  wt mk "$branch"
  local ok=1
  [ "$(cat "$expected/wéird name.env" 2>/dev/null)" = "VAL=1" ] || ok=0
  cd "$TEST_REPO"
  git worktree remove --force "$expected"
  rm -rf "$expected"
  [ "$ok" -eq 1 ]
}

@test "wt mk does not copy untracked files that are not gitignored" {
  local branch="wti-skip"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  echo "notes" > "$TEST_REPO/notes.txt"
  echo "notes.txt" > "$TEST_REPO/.worktreeinclude"
  wt mk "$branch"
  local present=0
  [ -e "$expected/notes.txt" ] && present=1
  cd "$TEST_REPO"
  git worktree remove --force "$expected"
  rm -rf "$expected"
  [ "$present" -eq 0 ]
}

@test "wt mk succeeds when .worktreeinclude is absent" {
  local branch="wti-none"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  run wt mk "$branch"
  [ "$status" -eq 0 ]
  git worktree remove --force "$expected"
  rm -rf "$expected"
}

# --- ad-hoc --pre-hook / --post-hook ---

@test "wt mk --post-hook runs the ad-hoc script with WT_BRANCH and WT_PATH" {
  local branch="adhoc-post"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  local script="$TEST_REPO/adhoc.sh"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH path=$WT_PATH" > /tmp/wt-adhoc-out\n' > "$script"
  chmod +x "$script"
  wt mk --post-hook "$script" "$branch"
  local out; out=$(cat /tmp/wt-adhoc-out); rm -f /tmp/wt-adhoc-out
  cd "$TEST_REPO"
  git worktree remove --force "$expected"
  [ "$out" = "branch=$branch path=$expected" ]
}

@test "wt mk accepts flags after the branch name" {
  local branch="adhoc-trailing"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  local script="$TEST_REPO/adhoc.sh"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH" > /tmp/wt-adhoc-out\n' > "$script"
  chmod +x "$script"
  wt mk "$branch" --post-hook "$script"
  local out; out=$(cat /tmp/wt-adhoc-out); rm -f /tmp/wt-adhoc-out
  cd "$TEST_REPO"
  git worktree remove --force "$expected"
  [ "$out" = "branch=$branch" ]
}

@test "wt mk --pre-hook failure aborts worktree creation" {
  local branch="adhoc-pre-abort"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  local script="$TEST_REPO/fail.sh"
  printf '#!/bin/sh\nexit 1\n' > "$script"
  chmod +x "$script"
  run wt mk --pre-hook "$script" "$branch"
  [ "$status" -ne 0 ]
  [ ! -d "$expected" ]
}

@test "wt mk runs a non-executable --post-hook via bash" {
  local branch="adhoc-nonexec"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  local script="$TEST_REPO/plain.sh"
  printf 'echo "branch=$WT_BRANCH" > /tmp/wt-adhoc-out\n' > "$script"
  wt mk --post-hook "$script" "$branch"
  local out; out=$(cat /tmp/wt-adhoc-out); rm -f /tmp/wt-adhoc-out
  cd "$TEST_REPO"
  git worktree remove --force "$expected"
  [ "$out" = "branch=$branch" ]
}

@test "wt mk errors when --post-hook file does not exist" {
  local branch="adhoc-missing"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  run wt mk --post-hook /nonexistent/path.sh "$branch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"hook file not found"* ]]
  [ -d "$expected" ] && { cd "$TEST_REPO"; git worktree remove --force "$expected"; }
  true
}
