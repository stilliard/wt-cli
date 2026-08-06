load ../helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- wt merged --claude ---

@test "wt merged --claude warns and falls back when claude CLI is missing" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature

  local stubbin; stubbin=$(mktemp -d)
  # only symlink the external commands wt.sh actually needs (git, awk) -
  # deliberately no claude, so `command -v claude` fails regardless of the host PATH
  ln -s "$(command -v git)" "$stubbin/git"
  ln -s "$(command -v awk)" "$stubbin/awk"

  PATH="$stubbin" run wt merged "$base" --claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude CLI not found"* ]]
  [[ "$output" == *"$TEST_REPO-feature"* ]]
  rm -rf "$stubbin"
}

@test "wt merged --claude lists agent sessions per worktree" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature

  local stubbin; stubbin=$(mktemp -d)
  # fake claude returns two sessions: one for our merged worktree's cwd, one
  # for an unrelated cwd - the unrelated one must be filtered out client-side
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
cat <<JSON
[
  {"id":"abc123","cwd":"$TEST_REPO-feature","name":"do the thing","state":"done"},
  {"id":"zzz999","cwd":"/somewhere/else","name":"unrelated","state":"done"}
]
JSON
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  PATH="$stubbin:$PATH" run wt merged "$base" --claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH"*"SESSION"*"NAME"*"STATE"* ]]
  [[ "$output" == *"feature"* ]]
  [[ "$output" == *"abc123"* ]]
  [[ "$output" == *"do the thing"* ]]
  [[ "$output" == *"done"* ]]
  [[ "$output" != *"zzz999"* ]]
  [[ "$output" != *"unrelated"* ]]
  rm -rf "$stubbin"
}

@test "wt merged --claude labels the main repo worktree distinctly instead of asserting a branch" {
  # the main repo worktree can itself end up in the merged list (checked out
  # to some other merged, non-base branch) - unlike a dedicated per-task
  # worktree, its current branch isn't a reliable record of what was checked
  # out when a past session actually ran there
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  cd "$TEST_REPO"
  git checkout -qb main-drift

  local stubbin; stubbin=$(mktemp -d)
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
cat <<JSON
[
  {"id":"main111","cwd":"$TEST_REPO","name":"main repo session","state":"done"}
]
JSON
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  PATH="$stubbin:$PATH" run wt merged "$base" --claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"main111"* ]]
  [[ "$output" == *"main repo session"* ]]
  [[ "$output" == *"(main, branch varies)"* ]]
  [[ "$output" != *"main-drift"* ]]
  rm -rf "$stubbin"
}

@test "wt merged --claude shows a placeholder row for worktrees with no sessions" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature

  local stubbin; stubbin=$(mktemp -d)
  cat > "$stubbin/claude" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  PATH="$stubbin:$PATH" run wt merged "$base" --claude
  [ "$status" -eq 0 ]
  [[ "$output" =~ feature.*-.*-.*- ]]
  rm -rf "$stubbin"
}

@test "wt merged --claude errors when jq is missing" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature

  local stubbin; stubbin=$(mktemp -d)
  cat > "$stubbin/claude" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
  chmod +x "$stubbin/claude"
  # only symlink the external commands wt.sh actually needs (git, awk) -
  # deliberately no jq, so `command -v jq` fails regardless of the host PATH
  ln -s "$(command -v git)" "$stubbin/git"
  ln -s "$(command -v awk)" "$stubbin/awk"

  PATH="$stubbin" run wt merged "$base" --claude
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq not found"* ]]
  rm -rf "$stubbin"
}

@test "wt merged --claude degrades gracefully when claude agents returns malformed output" {
  local base; base=$(git -C "$TEST_REPO" symbolic-ref --short HEAD)
  git -C "$TEST_REPO-feature" commit -q --allow-empty -m "feature commit"
  cd "$TEST_REPO"
  git merge -q feature

  local stubbin; stubbin=$(mktemp -d)
  # fake claude returns garbage instead of JSON (e.g. a crash/error message)
  cat > "$stubbin/claude" <<'EOF'
#!/usr/bin/env bash
echo 'not valid json at all'
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  PATH="$stubbin:$PATH" run wt merged "$base" --claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not read Claude Code agent sessions"* ]]
  [[ "$output" == *"feature"* ]]
  [[ "$output" =~ feature.*-.*-.*- ]]
  rm -rf "$stubbin"
}
