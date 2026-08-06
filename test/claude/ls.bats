load ../helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

# --- wt ls --claude ---

@test "wt ls --claude shows sessions for all worktrees, including the base one" {
  local stubbin; stubbin=$(mktemp -d)
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
cat <<JSON
[
  {"id":"base111","cwd":"$TEST_REPO","name":"base repo session","state":"done"},
  {"id":"feat222","cwd":"$TEST_REPO-feature","name":"feature session","state":"blocked"}
]
JSON
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  PATH="$stubbin:$PATH" run wt ls --claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH"*"SESSION"*"NAME"*"STATE"* ]]
  [[ "$output" == *"base111"* ]]
  [[ "$output" == *"base repo session"* ]]
  [[ "$output" == *"feat222"* ]]
  [[ "$output" == *"feature session"* ]]
  [[ "$output" == *"other"* ]]
  # the main repo worktree's branch can drift over time (unlike a dedicated
  # per-task worktree), so it should never be reported as a literal branch
  # name - only the distinct "(main, branch varies)" label
  [[ "$output" == *"(main, branch varies)"* ]]
  rm -rf "$stubbin"
}

@test "wt ls --claude attributes sessions via job state when the agents cwd is stale" {
  local stubbin; stubbin=$(mktemp -d)
  local sid="11111111-2222-3333-4444-555555555555"
  # `claude agents` reports the session's cwd as the main repo - the stale
  # dispatch-time value, recorded before the agent entered its worktree
  cat > "$stubbin/claude" <<EOF
#!/usr/bin/env bash
cat <<JSON
[
  {"id":"stale001","sessionId":"$sid","cwd":"$TEST_REPO","name":"stale cwd session","state":"done"}
]
JSON
EOF
  chmod +x "$stubbin/claude"
  cat > "$stubbin/jq" <<EOF
#!/usr/bin/env bash
exec "$(command -v jq)" "\$@"
EOF
  chmod +x "$stubbin/jq"

  # ...but the background-job state knows the real worktree
  local confdir; confdir=$(mktemp -d)
  mkdir -p "$confdir/jobs/stale001"
  cat > "$confdir/jobs/stale001/state.json" <<EOF
{"sessionId":"$sid","worktreePath":"$TEST_REPO-feature","worktreeBranch":"feature","state":"done"}
EOF

  CLAUDE_CONFIG_DIR="$confdir" PATH="$stubbin:$PATH" run wt ls --claude
  [ "$status" -eq 0 ]
  # attributed to the feature worktree row, not the main repo row
  [[ "$(echo "$output" | grep stale001)" == feature* ]]
  ! echo "$output" | grep "(main, branch varies)" | grep -q stale001
  rm -rf "$stubbin" "$confdir"
}

@test "wt ls --claude falls back to plain listing when claude CLI is missing" {
  local stubbin; stubbin=$(mktemp -d)
  ln -s "$(command -v git)" "$stubbin/git"
  ln -s "$(command -v awk)" "$stubbin/awk"

  PATH="$stubbin" run wt ls --claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude CLI not found"* ]]
  [[ "$output" == *"feature"* ]]
  rm -rf "$stubbin"
}
