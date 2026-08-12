load helpers

setup()    { wt_common_setup; }
teardown() { wt_common_teardown; }

@test "_wt_match prefers prefix matches" {
  run _wt_match "wo" worktree-foo other-foo
  [ "$output" = "worktree-foo" ]
}

@test "_wt_match falls back to substring matches" {
  run _wt_match "foo" worktree-foo worktree-bar
  [ "$output" = "worktree-foo" ]
}

@test "_wt_match returns nothing when there is no match" {
  run _wt_match "nope" worktree-foo worktree-bar
  [ -z "$output" ]
}

@test "_wt_match with an empty word returns everything" {
  run _wt_match "" a b c
  [ "${lines[0]}" = "a" ]
  [ "${lines[2]}" = "c" ]
}

@test "completion matches a branch without its worktree- prefix" {
  git -C "$TEST_REPO" worktree add -q "$TEST_REPO-wtf" -b worktree-fancy
  COMP_WORDS=(wt fancy); COMP_CWORD=1
  _wt_complete
  [ "${COMPREPLY[*]}" = "worktree-fancy" ]
  git -C "$TEST_REPO" worktree remove "$TEST_REPO-wtf"
}

@test "completion still offers subcommands on the first word" {
  COMP_WORDS=(wt mer); COMP_CWORD=1
  _wt_complete
  [ "${COMPREPLY[*]}" = "merged" ]
}

@test "an ambiguous substring completes nothing rather than mangling the word" {
  git -C "$TEST_REPO" worktree add -q "$TEST_REPO-wt1" -b worktree-fancy
  git -C "$TEST_REPO" worktree add -q "$TEST_REPO-wt2" -b worktree-fandango
  COMP_WORDS=(wt fan); COMP_CWORD=1
  _wt_complete
  [ ${#COMPREPLY[@]} -eq 0 ]
  git -C "$TEST_REPO" worktree remove "$TEST_REPO-wt1"
  git -C "$TEST_REPO" worktree remove "$TEST_REPO-wt2"
}

@test "completion after rm matches without the worktree- prefix" {
  git -C "$TEST_REPO" worktree add -q "$TEST_REPO-wtf" -b worktree-fancy
  COMP_WORDS=(wt rm fancy); COMP_CWORD=2
  _wt_complete
  [ "${COMPREPLY[*]}" = "worktree-fancy" ]
  git -C "$TEST_REPO" worktree remove "$TEST_REPO-wtf"
}
