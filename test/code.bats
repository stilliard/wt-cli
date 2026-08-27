load helpers

setup() {
  wt_common_setup
  # a fake editor on PATH that records the path it was handed
  FAKE_BIN=$(mktemp -d)
  EDITOR_LOG="$FAKE_BIN/log"
  for name in code cursor; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$name" "$EDITOR_LOG" > "$FAKE_BIN/$name"
    chmod +x "$FAKE_BIN/$name"
  done
  PATH="$FAKE_BIN:$PATH"
}

teardown() {
  rm -rf "$FAKE_BIN"
  wt_common_teardown
}

@test "wt code <name> opens the worktree in code by default" {
  wt code feature
  [ "$(cat "$EDITOR_LOG")" = "code $TEST_REPO-feature" ]
}

@test "wt code respects wt.editor" {
  git -C "$TEST_REPO" config wt.editor cursor
  wt code other
  [ "$(cat "$EDITOR_LOG")" = "cursor $TEST_REPO-other" ]
}

@test "wt code ~ opens the repo root" {
  cd "$TEST_REPO-feature"
  wt code "~"
  [ "$(cat "$EDITOR_LOG")" = "code $TEST_REPO" ]
}

@test "wt code with no name opens the worktree you are standing in" {
  cd "$TEST_REPO-feature"
  wt code
  [ "$(cat "$EDITOR_LOG")" = "code $TEST_REPO-feature" ]
}

@test "wt code with no name opens the repo root when not in a linked worktree" {
  wt code
  [ "$(cat "$EDITOR_LOG")" = "code $TEST_REPO" ]
}

@test "wt code with no name reports being outside a repo" {
  local outside; outside=$(mktemp -d)
  cd "$outside"
  run wt code
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git worktree"* ]]
  [ ! -f "$EDITOR_LOG" ]
  rm -rf "$outside"
}

@test "wt code returns an error for no match" {
  run wt code nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
  [ ! -f "$EDITOR_LOG" ]
}

@test "wt.editor can carry flags" {
  git -C "$TEST_REPO" config wt.editor 'cursor -n --wait'
  wt code feature
  [ "$(cat "$EDITOR_LOG")" = "cursor -n --wait $TEST_REPO-feature" ]
}

@test "wt.editor can quote a command path containing spaces" {
  mkdir "$FAKE_BIN/my editor"
  printf '#!/bin/sh\necho "spaced $*" >> "%s"\n' "$EDITOR_LOG" > "$FAKE_BIN/my editor/code"
  chmod +x "$FAKE_BIN/my editor/code"
  git -C "$TEST_REPO" config wt.editor "'$FAKE_BIN/my editor/code' -n"
  wt code feature
  [ "$(cat "$EDITOR_LOG")" = "spaced -n $TEST_REPO-feature" ]
}

@test "an empty wt.editor falls back to the default" {
  git -C "$TEST_REPO" config wt.editor ""
  wt code feature
  [ "$(cat "$EDITOR_LOG")" = "code $TEST_REPO-feature" ]
}

@test "an unparseable wt.editor is reported rather than run" {
  git -C "$TEST_REPO" config wt.editor 'code "'
  run wt code feature
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not parse"* ]]
  [ ! -f "$EDITOR_LOG" ]
}

@test "wt code reports a missing editor rather than failing silently" {
  git -C "$TEST_REPO" config wt.editor definitely-not-installed
  run wt code feature
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"wt.editor"* ]]
}

@test "completion offers code as a subcommand and branches after it" {
  COMP_WORDS=(wt cod); COMP_CWORD=1
  _wt_complete
  [ "${COMPREPLY[*]}" = "code" ]
  COMP_WORDS=(wt code feat); COMP_CWORD=2
  _wt_complete
  [ "${COMPREPLY[*]}" = "feature" ]
}

@test "wt code reads wt.editor from inside a linked worktree" {
  git -C "$TEST_REPO" config wt.editor cursor
  cd "$TEST_REPO-feature"
  wt code other
  [ "$(cat "$EDITOR_LOG")" = "cursor $TEST_REPO-other" ]
}
