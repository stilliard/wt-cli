load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_mk ---

@test "wt mk creates worktree under .claude/worktrees" {
  local branch="my-feature"
  local expected="$(wt_dest "$branch")"
  wt mk "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt mk cds into new worktree" {
  local branch="cd-test"
  local expected="$(wt_dest "$branch")"
  wt mk "$branch"
  [ "$PWD" = "$expected" ]
  git worktree remove "$expected"
}

@test "wt add alias creates worktree" {
  local branch="via-add"
  local expected="$(wt_dest "$branch")"
  wt add "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt mk replaces slashes in branch name with dashes" {
  local branch="type/my-thing"
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
  wt mk --base feature "$branch"
  local base_commit; base_commit=$(git -C "$TEST_REPO-feature" rev-parse HEAD)
  local new_commit; new_commit=$(git -C "$expected" rev-parse HEAD)
  [ "$new_commit" = "$base_commit" ]
  git worktree remove "$expected"
}

@test "wt mk reuses an existing local branch instead of failing" {
  git branch -q existing-local
  local want; want=$(git rev-parse existing-local)
  local expected="$(wt_dest existing-local)"
  wt mk existing-local
  [ "$(git -C "$expected" rev-parse HEAD)" = "$want" ]
  [ "$(git -C "$expected" rev-parse --abbrev-ref HEAD)" = "existing-local" ]
  cd "$TEST_REPO"
  git worktree remove "$expected"
}

@test "wt mk tracks a branch that only exists on origin" {
  local upstream; upstream=$(mktemp -d)
  git init -q --bare "$upstream"
  git remote add origin "$upstream"
  git push -q origin HEAD:refs/heads/remote-only
  git fetch -q origin
  git update-ref -d refs/heads/remote-only 2>/dev/null || true
  local expected="$(wt_dest remote-only)"
  wt mk remote-only
  local ok=1
  [ "$(git -C "$expected" rev-parse --abbrev-ref --symbolic-full-name @{u})" = "origin/remote-only" ] || ok=0
  cd "$TEST_REPO"
  git worktree remove "$expected"
  rm -rf "$upstream"
  [ "$ok" -eq 1 ]
}

@test "wt mk fails cleanly when the branch is checked out in another worktree" {
  local expected="$(wt_dest feature)"
  run wt mk feature
  [ "$status" -ne 0 ]
  [ ! -d "$expected" ]
}

@test "wt mk from inside a worktree creates alongside it, not nested" {
  wt mk first
  [ "$PWD" = "$(wt_dest first)" ]
  wt mk second
  [ -d "$(wt_dest second)" ]
  [ ! -d "$(wt_dest first)/.claude/worktrees/second" ]
  cd "$TEST_REPO"
  git worktree remove "$(wt_dest second)"
  git worktree remove "$(wt_dest first)"
}

@test "wt mk errors on unknown flag" {
  run wt mk --bogus value branch
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

# --- hooks ---

@test "post-mk hook receives WT_ROOT pointing at the main worktree" {
  local branch="hook-root"
  local expected="$(wt_dest "$branch")"
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\necho "$WT_ROOT" > /tmp/wt-hook-root\n' > "$TEST_REPO/.wt-hooks/post-mk"
  chmod +x "$TEST_REPO/.wt-hooks/post-mk"
  cd "$TEST_REPO-feature"
  wt mk "$branch"
  local out; out=$(cat /tmp/wt-hook-root); rm -f /tmp/wt-hook-root
  cd "$TEST_REPO"
  git worktree remove "$expected"
  [ "$out" = "$TEST_REPO" ]
}

@test "post-mk hook is called with WT_BRANCH and WT_PATH" {
  local branch="hook-test"
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
  run wt mk "$branch"
  [ "$status" -eq 0 ]
  git worktree remove "$expected"
}

@test "pre-mk hook failure aborts worktree creation" {
  local branch="pre-mk-abort"
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
  run wt mk "$branch"
  [ "$status" -eq 0 ]
  git worktree remove --force "$expected"
  rm -rf "$expected"
}

# --- ad-hoc --pre-hook / --post-hook ---

@test "wt mk --post-hook runs the ad-hoc script with WT_BRANCH and WT_PATH" {
  local branch="adhoc-post"
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
  local script="$TEST_REPO/fail.sh"
  printf '#!/bin/sh\nexit 1\n' > "$script"
  chmod +x "$script"
  run wt mk --pre-hook "$script" "$branch"
  [ "$status" -ne 0 ]
  [ ! -d "$expected" ]
}

@test "wt mk runs a non-executable --post-hook via bash" {
  local branch="adhoc-nonexec"
  local expected="$(wt_dest "$branch")"
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
  local expected="$(wt_dest "$branch")"
  run wt mk --post-hook /nonexistent/path.sh "$branch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"hook file not found"* ]]
  [ -d "$expected" ] && { cd "$TEST_REPO"; git worktree remove --force "$expected"; }
  true
}
