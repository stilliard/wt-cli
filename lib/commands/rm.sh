# remove a worktree by branch name or directory basename
_wt_rm() {
  local pre_hook="" post_hook="" claude=0
  local -a args
  while [ $# -gt 0 ]; do
    case "$1" in
      --pre-hook)  pre_hook="$2";  shift 2 ;;
      --post-hook) post_hook="$2"; shift 2 ;;
      --claude)    claude=1;       shift ;;
      --)          shift; args+=("$@"); break ;;
      --*) echo "wt: unknown flag '$1'" >&2; return 1 ;;
      *)   args+=("$1"); shift ;;
    esac
  done
  set -- "${args[@]}"
  local root; root=$(_wt_root) || return 1
  local target
  target=$(_wt_resolve "${1?usage: wt rm <name> [--claude] [--pre-hook P] [--post-hook P]}")
  [ -z "$target" ] && { echo "wt: no worktree matching '$1'" >&2; return 1; }
  # git would refuse this anyway, but only after the pre-rm hook had already run
  [ "$target" = "$root" ] && { echo "wt: refusing to remove the main worktree" >&2; return 1; }
  # preflight claude/jq before doing anything destructive
  if [ "$claude" -eq 1 ]; then
    _wt_claude_init
    case $? in
      1) claude=0 ;;  # claude CLI missing (warned) - proceed without it
      2) return 1 ;;
    esac
  fi
  cd "$target"
  _WT_HOOK_ROOT="$root" _wt_run_hook pre-rm "$1" "$target" || { cd "$root"; return 1; }
  _wt_run_adhoc_hook "$pre_hook" "$1" "$target" || { cd "$root"; return 1; }
  cd "$root"
  local rc=0
  git worktree remove "$target" || return $?
  _WT_HOOK_ROOT="$root" _wt_run_hook post-rm "$1" "$target"
  _wt_run_adhoc_hook "$post_hook" "$1" "$target"
  if [ "$claude" -eq 1 ]; then
    _wt_claude_rm_sessions "$target" || rc=1
  fi
  return "$rc"
}
