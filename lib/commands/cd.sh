# navigate to a worktree by branch name or directory basename; ~ (or root) goes
# to the repo root
_wt_cd() {
  local target; target=$(_wt_target "${1?usage: wt <name>}") || return 1
  cd "$target"
}
