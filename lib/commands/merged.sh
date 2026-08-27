# list worktrees whose branch is already merged into main/master (candidates for removal)
_wt_merged() {
  local base="" show_claude=0 do_rm=0 assume_yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --claude) show_claude=1; shift ;;
      --rm)     do_rm=1;       shift ;;
      -y|--yes) assume_yes=1;  shift ;;
      --*) echo "wt: unknown flag '$1'" >&2; return 1 ;;
      *)   base="$1"; shift ;;
    esac
  done

  if [ -z "$base" ]; then
    if git show-ref --verify --quiet refs/heads/main; then
      base=main
    elif git show-ref --verify --quiet refs/heads/master; then
      base=master
    else
      echo "wt: could not detect default branch (no main or master); specify one: wt merged <base>" >&2
      return 1
    fi
  else
    git show-ref --verify --quiet "refs/heads/$base" || { echo "wt: branch '$base' not found" >&2; return 1; }
  fi

  local merged
  merged=$(git branch --merged "$base" --format='%(refname:short)')

  local list
  list=$(git worktree list --porcelain | awk -v base="$base" -v merged="$merged" '
    BEGIN { n = split(merged, arr, "\n"); for (i = 1; i <= n; i++) mset[arr[i]] = 1 }
    /^worktree / { path = $2 }
    /^branch /   { branch = $2; sub("refs/heads/", "", branch) }
    /^$/ {
      if (branch != "" && branch != base && (branch in mset)) print path "\t" branch
      path = ""; branch = ""
    }
  ')
  [ -z "$list" ] && return 0

  if [ "$show_claude" -eq 0 ]; then
    printf '%s\n' "$list" | awk -F'\t' '{ print $1 "  [" $2 "]" }'
  else
    _wt_claude_init
    case $? in
      1) show_claude=0 ;;  # claude CLI missing (warned) - continue without it
      2) printf '%s\n' "$list" | awk -F'\t' '{ print $1 "  [" $2 "]" }'; return 1 ;;
    esac
    if [ "$show_claude" -eq 1 ]; then
      printf '%s\n' "$list" | _wt_claude_table
    else
      printf '%s\n' "$list" | awk -F'\t' '{ print $1 "  [" $2 "]" }'
    fi
  fi
  [ "$do_rm" -eq 0 ] && return 0

  local count; count=$(printf '%s\n' "$list" | grep -c .)
  if [ "$assume_yes" -eq 0 ]; then
    local suffix=""
    [ "$show_claude" -eq 1 ] && suffix=" and their Claude Code sessions"
    printf 'wt: remove %s worktree(s)%s? [y/N] ' "$count" "$suffix"
    local ans; read -r ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "wt: aborted"; return 1 ;;
    esac
  fi

  # never remove the main working tree, even if it's on a merged branch
  # NB: never name a shell variable "path" - zsh ties it to $PATH, so a
  # `local path` (or a bare `read -r path`) wipes PATH for everything below
  local main_wt wt_path branch failed=0 removed=""
  main_wt=$(_wt_root)
  while IFS=$'\t' read -r wt_path branch; do
    [ -z "$wt_path" ] && continue
    if [ "$wt_path" = "$main_wt" ]; then
      echo "wt: skipping main worktree [$branch]" >&2
      continue
    fi
    # branches are cleaned up in one batch below, so don't let _wt_rm ask per worktree
    if [ "$show_claude" -eq 1 ]; then
      _WT_SKIP_BRANCH_CLEANUP=1 _wt_rm --claude "$branch" || { failed=1; continue; }
    else
      _WT_SKIP_BRANCH_CLEANUP=1 _wt_rm "$branch" || { failed=1; continue; }
    fi
    removed="$removed$branch
"
  done <<< "$list"

  _wt_merged_rm_branches "$removed" "$assume_yes" "$base"
  [ "$failed" -eq 0 ]
}

# delete the branches of the worktrees just removed. They are all merged into the
# base by construction, so git branch -d accepts them; a refusal is git's own error
# on stderr and doesn't fail the command, same as the single-worktree path.
_wt_merged_rm_branches() {
  local removed="$1" assume_yes="$2" base="$3" b
  [ -n "$removed" ] || return 0
  if [ "$assume_yes" -eq 0 ]; then
    local count; count=$(printf '%s' "$removed" | grep -c .)
    printf 'wt: also delete %s branch(es)? [y/N] ' "$count"
    local ans=""; read -r ans || true   # EOF (no answer piped in) means keep
    case "$ans" in
      y|Y|yes|YES) ;;
      *) return 0 ;;
    esac
  fi
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    [ "$b" = "$base" ] && continue
    _wt_del_branch "$b" || true
  done <<< "$removed"
  return 0
}
