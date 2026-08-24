# list all worktrees with their paths and branches
_wt_ls() {
  local show_claude=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --claude) show_claude=1; shift ;;
      --*) echo "wt: unknown flag '$1'" >&2; return 1 ;;
      *)   echo "wt: unknown argument '$1'" >&2; return 1 ;;
    esac
  done
  [ "$show_claude" -eq 0 ] && { git worktree list; return 0; }

  local list
  list=$(git worktree list --porcelain | awk '
    /^worktree / { path = $2 }
    /^branch /   { branch = $2; sub("refs/heads/", "", branch) }
    /^detached$/ { branch = "(detached)" }
    /^$/ { if (path != "") print path "\t" branch; path = ""; branch = "" }
  ')
  [ -z "$list" ] && return 0

  _wt_claude_init
  case $? in
    1) git worktree list; return 0 ;;
    2) git worktree list; return 1 ;;
  esac
  printf '%s\n' "$list" | _wt_claude_table
}
