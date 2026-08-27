load ../helpers

setup() {
  wt_common_setup
  FAKE_BIN=$(mktemp -d)
  CLAUDE_LOG="$FAKE_BIN/log"
  # a fake `claude` that answers `agents --json` with SESSIONS_JSON and records
  # argv + cwd for any other invocation
  cat > "$FAKE_BIN/claude" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "agents" ]; then
  printf '%s' "\${SESSIONS_JSON:-[]}"
  exit 0
fi
echo "\$PWD | claude \$*" >> "$CLAUDE_LOG"
EOF
  chmod +x "$FAKE_BIN/claude"
  PATH="$FAKE_BIN:$PATH"
}

teardown() {
  rm -rf "$FAKE_BIN"
  wt_common_teardown
}

@test "wt claude resumes the newest session recorded for the worktree" {
  SESSIONS_JSON='[
    {"id":"old1","sessionId":"11111111-1111-1111-1111-111111111111","cwd":"'$TEST_REPO'-feature","startedAt":100,"state":"done"},
    {"id":"new1","sessionId":"22222222-2222-2222-2222-222222222222","cwd":"'$TEST_REPO'-feature","startedAt":200,"state":"done"}
  ]'
  export SESSIONS_JSON
  run wt claude feature
  [ "$status" -eq 0 ]
  [[ "$output" == *"resuming Claude session 22222222-2222-2222-2222-222222222222"* ]]
  [ "$(cat "$CLAUDE_LOG")" = "$TEST_REPO-feature | claude --resume 22222222-2222-2222-2222-222222222222" ]
}

@test "wt claude starts a new session when the worktree has none" {
  SESSIONS_JSON='[{"id":"o","sessionId":"33333333-3333-3333-3333-333333333333","cwd":"'$TEST_REPO'-other","startedAt":1}]'
  export SESSIONS_JSON
  run wt claude feature
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Claude session found"* ]]
  [ "$(cat "$CLAUDE_LOG")" = "$TEST_REPO-feature | claude " ]
}

@test "wt claude ignores session rows with no session id" {
  # the session you are sitting in shows up with an empty id
  SESSIONS_JSON='[{"id":"","sessionId":"","cwd":"'$TEST_REPO'-feature","state":""}]'
  export SESSIONS_JSON
  run wt claude feature
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Claude session found"* ]]
  [[ "$output" != *"--resume"* ]]
}

@test "wt claude --new starts fresh without looking up sessions" {
  SESSIONS_JSON='[{"id":"a","sessionId":"44444444-4444-4444-4444-444444444444","cwd":"'$TEST_REPO'-feature","startedAt":1}]'
  export SESSIONS_JSON
  run wt claude feature --new
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_LOG")" = "$TEST_REPO-feature | claude " ]
}

@test "wt claude attributes a session via job state when the agents cwd is stale" {
  local sid="55555555-5555-5555-5555-555555555555"
  SESSIONS_JSON='[{"id":"stale1","sessionId":"'$sid'","cwd":"'$TEST_REPO'","startedAt":1,"state":"done"}]'
  export SESSIONS_JSON
  local confdir; confdir=$(mktemp -d)
  mkdir -p "$confdir/jobs/stale1"
  echo '{"sessionId":"'$sid'","worktreePath":"'$TEST_REPO'-feature"}' > "$confdir/jobs/stale1/state.json"

  CLAUDE_CONFIG_DIR="$confdir" run wt claude feature
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_LOG")" = "$TEST_REPO-feature | claude --resume $sid" ]
  rm -rf "$confdir"
}

@test "wt claude passes extra arguments through to claude" {
  SESSIONS_JSON='[]'
  export SESSIONS_JSON
  run wt claude feature --new --effort high
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_LOG")" = "$TEST_REPO-feature | claude --effort high" ]
}

@test "wt claude ~ targets the repo root" {
  SESSIONS_JSON='[]'
  export SESSIONS_JSON
  cd "$TEST_REPO-feature"
  run wt claude "~" --new
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_LOG")" = "$TEST_REPO | claude " ]
}

@test "wt claude does not move the caller's shell" {
  SESSIONS_JSON='[]'
  export SESSIONS_JSON
  local before="$PWD"
  wt claude feature --new
  [ "$PWD" = "$before" ]
}

@test "wt claude with no name reports usage" {
  run wt claude
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: wt claude"* ]]
  [ ! -f "$CLAUDE_LOG" ]
}

@test "wt claude reports an unknown worktree" {
  run wt claude nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
  [ ! -f "$CLAUDE_LOG" ]
}

@test "completion offers claude as a subcommand and branches after it" {
  COMP_WORDS=(wt claud); COMP_CWORD=1
  _wt_complete
  [ "${COMPREPLY[*]}" = "claude" ]
  COMP_WORDS=(wt claude feat); COMP_CWORD=2
  _wt_complete
  [ "${COMPREPLY[*]}" = "feature" ]
}
