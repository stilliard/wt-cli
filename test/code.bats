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

@test "wt code returns an error for no match" {
  run wt code nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
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
