# navigate to a worktree by branch name or directory basename; ~ (or root) goes
# to the repo root. The shell expands a bare ~ before wt sees it, so $HOME counts
# as ~ too. A real worktree still wins, so a branch named "root" keeps working.
_wt_cd() {
  local name="${1?usage: wt <name>}" target root
  if [ "$name" != "~" ] && { [ -z "$HOME" ] || [ "$name" != "$HOME" ]; }; then
    target=$(_wt_resolve "$name")
  fi
  if [ -z "$target" ]; then
    case "$name" in
      "~"|root|"${HOME:-~}") root=$(_wt_root) || return 1; cd "$root"; return ;;
    esac
    echo "wt: no worktree matching '$name'" >&2
    return 1
  fi
  cd "$target"
}
