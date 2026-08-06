setup() {
  # create a temp bare repo and two worktrees
  TEST_REPO=$(mktemp -d)
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "init"

  git worktree add -q "$TEST_REPO-feature" -b feature
  git worktree add -q "$TEST_REPO-other" -b other

  source "$BATS_TEST_DIRNAME/../wt.sh"
}

teardown() {
  rm -rf "$TEST_REPO" "$TEST_REPO-feature" "$TEST_REPO-other"
}

# --- _wt_resolve ---

@test "_wt_resolve finds worktree by branch name" {
  result=$(_wt_resolve feature)
  [ "$result" = "$TEST_REPO-feature" ]
}

@test "_wt_resolve finds worktree by directory basename" {
  result=$(_wt_resolve "$(basename "$TEST_REPO-other")")
  [ "$result" = "$TEST_REPO-other" ]
}

@test "_wt_resolve returns empty string for no match" {
  result=$(_wt_resolve nonexistent)
  [ -z "$result" ]
}

# --- _wt_cd ---

@test "wt <name> navigates to worktree" {
  _wt_cd feature
  [ "$PWD" = "$TEST_REPO-feature" ]
}

@test "wt cd <name> navigates to worktree" {
  wt cd other
  [ "$PWD" = "$TEST_REPO-other" ]
}

@test "wt <name> returns error for no match" {
  run _wt_cd nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
}

# --- _wt_ls ---

@test "wt ls lists worktrees" {
  run _wt_ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO "* ]]
  [[ "$output" == *"feature"* ]]
  [[ "$output" == *"other"* ]]
}

@test "wt with no args lists worktrees" {
  run wt
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt list alias works" {
  run wt list
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}

@test "wt ls errors on unknown flag" {
  run wt ls --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

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
exec $(command -v jq) "\$@"
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
exec $(command -v jq) "\$@"
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
}

# --- _wt_mk ---

@test "wt mk creates worktree as repo sibling" {
  local branch="my-feature"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt mk "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt mk cds into new worktree" {
  local branch="cd-test"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt mk "$branch"
  [ "$PWD" = "$expected" ]
  git worktree remove "$expected"
}

@test "wt add alias creates worktree" {
  local branch="via-add"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt add "$branch"
  [ -d "$expected" ]
  git worktree remove "$expected"
}

@test "wt mk replaces slashes in branch name with dashes" {
  local branch="type/my-thing"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-type-my-thing"
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
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  wt mk --base feature "$branch"
  local base_commit; base_commit=$(git -C "$TEST_REPO-feature" rev-parse HEAD)
  local new_commit; new_commit=$(git -C "$expected" rev-parse HEAD)
  [ "$new_commit" = "$base_commit" ]
  git worktree remove "$expected"
}

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

@test "wt rm returns error for no match" {
  run wt rm nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"no worktree matching"* ]]
}

# --- _wt_prune ---

@test "wt prune runs without error" {
  run wt prune
  [ "$status" -eq 0 ]
}

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
exec $(command -v jq) "\$@"
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
exec $(command -v jq) "\$@"
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
exec $(command -v jq) "\$@"
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
exec $(command -v jq) "\$@"
EOF
  chmod +x "$stubbin/jq"

  PATH="$stubbin:$PATH" run wt merged "$base" --claude
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not read Claude Code agent sessions"* ]]
  [[ "$output" == *"feature"* ]]
  [[ "$output" =~ feature.*-.*-.*- ]]
  rm -rf "$stubbin"
}

# --- help ---

@test "wt help prints usage" {
  run wt help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "wt --help prints usage" {
  run wt --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "wt -h prints usage" {
  run wt -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# --- hooks ---

@test "post-mk hook is called with WT_BRANCH and WT_PATH" {
  local branch="hook-test"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH path=$WT_PATH" > /tmp/wt-hook-out' > "$TEST_REPO/.wt-hooks/post-mk"
  chmod +x "$TEST_REPO/.wt-hooks/post-mk"
  wt mk "$branch"
  local out; out=$(cat /tmp/wt-hook-out); rm -f /tmp/wt-hook-out
  git worktree remove "$expected"
  [[ "$out" == "branch=$branch path=$expected" ]]
}

@test "post-rm hook is called with WT_BRANCH and WT_PATH" {
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\necho "branch=$WT_BRANCH path=$WT_PATH" > /tmp/wt-hook-out' > "$TEST_REPO/.wt-hooks/post-rm"
  chmod +x "$TEST_REPO/.wt-hooks/post-rm"
  wt rm feature
  local out; out=$(cat /tmp/wt-hook-out); rm -f /tmp/wt-hook-out
  [[ "$out" == "branch=feature path=$TEST_REPO-feature" ]]
}

@test "hooks are skipped when .wt-hooks dir does not exist" {
  local branch="no-hook"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  run wt mk "$branch"
  [ "$status" -eq 0 ]
  git worktree remove "$expected"
}

@test "pre-mk hook failure aborts worktree creation" {
  local branch="pre-mk-abort"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\nexit 1' > "$TEST_REPO/.wt-hooks/pre-mk"
  chmod +x "$TEST_REPO/.wt-hooks/pre-mk"
  run wt mk "$branch"
  [ "$status" -ne 0 ]
  [ ! -d "$expected" ]
}

@test "pre-rm hook failure aborts worktree removal" {
  mkdir -p "$TEST_REPO/.wt-hooks"
  printf '#!/bin/sh\nexit 1' > "$TEST_REPO/.wt-hooks/pre-rm"
  chmod +x "$TEST_REPO/.wt-hooks/pre-rm"
  run wt rm feature
  [ "$status" -ne 0 ]
  [ -d "$TEST_REPO-feature" ]
}

# --- .worktreeinclude ---

@test "wt mk copies gitignored files listed in .worktreeinclude" {
  local branch="wti-copy"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
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
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
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
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
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
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  run wt mk "$branch"
  [ "$status" -eq 0 ]
  git worktree remove --force "$expected"
  rm -rf "$expected"
}

# --- ad-hoc --pre-hook / --post-hook ---

@test "wt mk --post-hook runs the ad-hoc script with WT_BRANCH and WT_PATH" {
  local branch="adhoc-post"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
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
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
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
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  local script="$TEST_REPO/fail.sh"
  printf '#!/bin/sh\nexit 1\n' > "$script"
  chmod +x "$script"
  run wt mk --pre-hook "$script" "$branch"
  [ "$status" -ne 0 ]
  [ ! -d "$expected" ]
}

@test "wt mk runs a non-executable --post-hook via bash" {
  local branch="adhoc-nonexec"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  local script="$TEST_REPO/plain.sh"
  printf 'echo "branch=$WT_BRANCH" > /tmp/wt-adhoc-out\n' > "$script"
  wt mk --post-hook "$script" "$branch"
  local out; out=$(cat /tmp/wt-adhoc-out); rm -f /tmp/wt-adhoc-out
  cd "$TEST_REPO"
  git worktree remove --force "$expected"
  [ "$out" = "branch=$branch" ]
}

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

@test "wt mk errors on unknown flag" {
  run wt mk --bogus value branch
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "wt mk errors when --post-hook file does not exist" {
  local branch="adhoc-missing"
  local expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-$branch"
  run wt mk --post-hook /nonexistent/path.sh "$branch"
  [ "$status" -ne 0 ]
  [[ "$output" == *"hook file not found"* ]]
  [ -d "$expected" ] && { cd "$TEST_REPO"; git worktree remove --force "$expected"; }
  true
}

# --- dispatcher aliases ---

@test "wt ls alias works" {
  run wt ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature"* ]]
}
