# list all worktrees with their paths and branches
_wt_ls() {
  local show_claude=0 show_only=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --claude) show_claude=1; shift ;;
      --branch|--path)
        [ -n "$show_only" ] && [ "$show_only" != "${1#--}" ] && { echo "wt: --branch and --path are mutually exclusive" >&2; return 1; }
        show_only="${1#--}"; shift ;;
      --*) echo "wt: unknown flag '$1'" >&2; return 1 ;;
      *)   echo "wt: unknown argument '$1'" >&2; return 1 ;;
    esac
  done
  if [ -n "$show_only" ] && [ "$show_claude" -eq 1 ]; then
    echo "wt: --claude can't be combined with --$show_only" >&2
    return 1
  fi

  if [ -n "$show_only" ]; then
    local porcelain
    porcelain=$(git worktree list --porcelain) || return 1
    if [ "$show_only" = "path" ]; then
      printf '%s\n' "$porcelain" | awk '/^worktree /{ $1=""; sub(/^ /,""); print }'
    else
      printf '%s\n' "$porcelain" | awk '
        /^branch /   { sub("refs/heads/", "", $2); print $2 }
        /^detached$/ { print "(detached)" }
      '
    fi
    return 0
  fi

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
