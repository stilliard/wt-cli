load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- _wt_merged ---

@test "wt merged lists a worktree whose branch is merged into base, excludes unmerged and base" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  git -C "$TEST_REPO-other" commit -q --allow-empty -m "other commit"
  cd "$TEST_REPO"
  git merge -q feature

  run wt merged "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO-feature"* ]]
  [[ "$output" == *"[feature]"* ]]
  [[ "$output" != *"[other]"* ]]
  [[ "$output" != *"[$base]"* ]]
}

@test "wt merged auto-detects main when no base is given" {
  local tmp2; tmp2=$(mktemp -d)
  cd "$tmp2"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit -q --allow-empty -m init
  git branch -m main
  git worktree add -q "$tmp2-feature" -b feature
  git -C "$tmp2-feature" commit -q --allow-empty -m "feature commit"
  git merge -q feature

  run wt merged
  [ "$status" -eq 0 ]
  [[ "$output" == *"$tmp2-feature"* ]]

  git worktree remove --force "$tmp2-feature"
  cd "$TEST_REPO"
  rm -rf "$tmp2" "$tmp2-feature"
}

@test "wt merged errors when neither main nor master exists" {
  local tmp2; tmp2=$(mktemp -d)
  cd "$tmp2"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit -q --allow-empty -m init
  git branch -m custom-base

  run wt merged
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not detect default branch"* ]]

  cd "$TEST_REPO"
  rm -rf "$tmp2"
}

@test "wt merged errors when given an unknown base branch" {
  run wt merged nonexistent-base
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "wt merged accepts an explicit base branch" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  run wt merged "$base"
  [ "$status" -eq 0 ]
}

@test "wt merged errors on unknown flag" {
  run wt merged --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

# --- --rm ---

@test "wt merged --rm -y removes merged worktrees and keeps unmerged ones" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  git -C "$TEST_REPO-other" commit -q --allow-empty -m "other commit"
  cd "$TEST_REPO"
  git merge -q feature

  run wt merged "$base" --rm -y
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-feature" ]
  [ -d "$TEST_REPO-other" ]
}

@test "wt merged --rm asks for confirmation and aborts on anything but yes" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature

  run wt merged "$base" --rm <<< "n"
  [ "$status" -ne 0 ]
  [[ "$output" == *"aborted"* ]]
  [ -d "$TEST_REPO-feature" ]
}

@test "wt merged --rm accepts y at the confirmation prompt" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature

  run wt merged "$base" --rm <<< "y"
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-feature" ]
}

@test "wt merged --rm -y returns non-zero when a removal fails" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature
  # dirty worktree - git worktree remove refuses without --force
  echo "wip" > "$TEST_REPO-feature/untracked.txt"

  run wt merged "$base" --rm -y
  [ "$status" -ne 0 ]
  [ -d "$TEST_REPO-feature" ]
}

@test "wt merged --rm never removes the main worktree" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature
  # main checkout sits on a merged, non-base branch - listed, but must be skipped
  git checkout -qb main-drift

  run wt merged "$base" --rm -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping main worktree"* ]]
  [ -d "$TEST_REPO" ]
  [ ! -d "$TEST_REPO-feature" ]
}
