load ../helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- wt rm --claude ---

@test "wt rm --claude removes the worktree and deletes its Claude sessions" {
  local stubbin; stubbin=$(mktemp -d)
  # fake claude: log `rm <id>` calls, and report one session for the
  # feature worktree from `agents --json --all`
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "rm" ]; then
  echo "\$2" >> "$stubbin/rm.log"
  exit 0
fi
cat <<JSON
[{"id":"abc123","cwd":"$TEST_REPO-feature","name":"feature session","state":"done"}]
JSON
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  CLAUDE_CONFIG_DIR="$stubbin" PATH="$stubbin:$PATH" run wt rm --claude feature
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-feature" ]
  [[ "$output" == *"deleted Claude session abc123"* ]]
  [ "$(cat "$stubbin/rm.log")" = "abc123" ]
  rm -rf "$stubbin"
}

@test "wt rm --claude still removes a worktree that has no sessions" {
  local stubbin; stubbin=$(mktemp -d)
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "rm" ]; then
  echo "\$2" >> "$stubbin/rm.log"
  exit 0
fi
echo '[]'
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  CLAUDE_CONFIG_DIR="$stubbin" PATH="$stubbin:$PATH" run wt rm --claude feature
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-feature" ]
  [ ! -e "$stubbin/rm.log" ]
  rm -rf "$stubbin"
}

@test "wt rm --claude does not delete sessions when the worktree removal fails" {
  local stubbin; stubbin=$(mktemp -d)
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "rm" ]; then
  echo "\$2" >> "$stubbin/rm.log"
  exit 0
fi
cat <<JSON
[{"id":"abc123","cwd":"$TEST_REPO-feature","name":"feature session","state":"done"}]
JSON
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  # dirty worktree - git worktree remove refuses without --force
  echo "wip" > "$TEST_REPO-feature/untracked.txt"

  CLAUDE_CONFIG_DIR="$stubbin" PATH="$stubbin:$PATH" run wt rm --claude feature
  [ "$status" -ne 0 ]
  [ -d "$TEST_REPO-feature" ]
  [ ! -e "$stubbin/rm.log" ]
  rm -rf "$stubbin"
}

@test "wt rm --claude aborts before removal when jq is missing" {
  local stubbin; stubbin=$(mktemp -d)
  cat > "$stubbin/claude" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
  chmod +x "$stubbin/claude"
  # claude present but no jq - preflight must fail before anything is removed
  ln -s "$(command -v git)" "$stubbin/git"
  ln -s "$(command -v awk)" "$stubbin/awk"
  ln -s "$(command -v dirname)" "$stubbin/dirname"

  PATH="$stubbin" run wt rm --claude feature
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq not found"* ]]
  [ -d "$TEST_REPO-feature" ]
  rm -rf "$stubbin"
}

@test "wt rm --claude never runs claude rm for sessions without an id" {
  local stubbin; stubbin=$(mktemp -d)
  # session matching the worktree but with no id field at all
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "rm" ]; then
  echo "\$2" >> "$stubbin/rm.log"
  exit 0
fi
cat <<JSON
[{"cwd":"$TEST_REPO-feature","name":"no id session","state":"done"}]
JSON
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  CLAUDE_CONFIG_DIR="$stubbin" PATH="$stubbin:$PATH" run wt rm --claude feature
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_REPO-feature" ]
  [ ! -e "$stubbin/rm.log" ]
  [[ "$output" != *"null"* ]]
  rm -rf "$stubbin"
}
