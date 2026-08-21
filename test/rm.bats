load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

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

@test "wt rm refuses to remove the main worktree by branch name" {
  local branch; branch=$(git -C "$TEST_REPO" rev-parse --abbrev-ref HEAD)
  run wt rm "$branch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to remove the main worktree"* ]]
  [ -d "$TEST_REPO/.git" ]
}

@test "wt rm does not run the pre-rm hook for the main worktree" {
  local branch; branch=$(git -C "$TEST_REPO" rev-parse --abbrev-ref HEAD)
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\ntouch /tmp/wt-mainguard-ran\n' > "$TEST_REPO/.wt-hooks/pre-rm"
  chmod +x "$TEST_REPO/.wt-hooks/pre-rm"
  rm -f /tmp/wt-mainguard-ran
  run wt rm "$branch"
  local ran=0; [ -e /tmp/wt-mainguard-ran ] && ran=1
  rm -f /tmp/wt-mainguard-ran
  [ "$status" -ne 0 ]
  [ "$ran" -eq 0 ]
}

@test "wt rm still removes a linked worktree from inside another worktree" {
  cd "$TEST_REPO-feature"
  run wt rm other
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-other" ]
}

@test "wt rm returns error for no match" {
  run wt rm nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
}

# --- hooks ---

@test "post-rm hook is called with WT_BRANCH and WT_PATH" {
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH path=$WT_PATH" > /tmp/wt-hook-out' > "$TEST_REPO/.wt-hooks/post-rm"
  chmod +x "$TEST_REPO/.wt-hooks/post-rm"
  wt rm feature
  local out; out=$(cat /tmp/wt-hook-out); rm -f /tmp/wt-hook-out
  [[ "$out" == "branch=feature path=$TEST_REPO-feature" ]]
}

@test "post-rm hook is not called when removal fails" {
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\ntouch /tmp/wt-postrm-ran' > "$TEST_REPO/.wt-hooks/post-rm"
  chmod +x "$TEST_REPO/.wt-hooks/post-rm"
  rm -f /tmp/wt-postrm-ran
  # dirty worktree - git worktree remove refuses without --force
  echo "wip" > "$TEST_REPO-feature/untracked.txt"
  run wt rm feature
  [ "$status" -ne 0 ]
  [ -d "$TEST_REPO-feature" ]
  [ ! -e /tmp/wt-postrm-ran ]
}

@test "pre-rm hook failure aborts worktree removal" {
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\nexit 1' > "$TEST_REPO/.wt-hooks/pre-rm"
  chmod +x "$TEST_REPO/.wt-hooks/pre-rm"
  run wt rm feature
  [ "$status" -ne 0 ]
  [ -d "$TEST_REPO-feature" ]
}

# --- ad-hoc --pre-hook / --post-hook ---

@test "wt rm --pre-hook runs before removal" {
  local script="$TEST_REPO/rm-pre.sh"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH path=$WT_PATH" > /tmp/wt-adhoc-out\n' > "$script"
  chmod +x "$script"
  wt rm --pre-hook "$script" feature
  local out; out=$(cat /tmp/wt-adhoc-out); rm -f /tmp/wt-adhoc-out
  [ "$out" = "branch=feature path=$TEST_REPO-feature" ]
  [ ! -d "$TEST_REPO-feature" ]
}

@test "wt rm --pre-hook failure aborts removal" {
  local script="$TEST_REPO/fail.sh"
  printf '#!/bin/sh\nexit 1\n' > "$script"
  chmod +x "$script"
  run wt rm --pre-hook "$script" feature
  [ "$status" -ne 0 ]
  [ -d "$TEST_REPO-feature" ]
}
