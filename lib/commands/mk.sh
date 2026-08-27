# create a new worktree (optional explicit path as second arg)
_wt_mk() {
  local pre_hook="" post_hook="" base=""
  local -a args
  while [ $# -gt 0 ]; do
    case "$1" in
      --pre-hook)  pre_hook="$2";  shift 2 ;;
      --post-hook) post_hook="$2"; shift 2 ;;
      --base)      base="$2";      shift 2 ;;
      --)          shift; args+=("$@"); break ;;
      --*) echo "wt: unknown flag '$1'" >&2; return 1 ;;
      *)   args+=("$1"); shift ;;
    esac
  done
  set -- "${args[@]}"
  local branch="${1?usage: wt mk <branch> [path] [--base B] [--pre-hook P] [--post-hook P]}"
  local root; root=$(_wt_root) || return 1
  local safe; safe=$(_wt_safe_name "$branch")
  local dest="$2"
  [ -n "$dest" ] || { dest=$(_wt_dest_default "$root" "$safe") || return 1; }
  _wt_warn_unignored "$root" "$dest"
  _WT_HOOK_ROOT="$root" _wt_run_hook pre-mk "$branch" "$dest" || return
  _wt_run_adhoc_hook "$pre_hook" "$branch" "$dest" || return
  if [ -n "$base" ]; then
    git worktree add "$dest" -b "$branch" "$base" || return
  elif git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$dest" "$branch" || return
  elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git worktree add --track -b "$branch" "$dest" "origin/$branch" || return
  else
    git worktree add "$dest" -b "$branch" || return
  fi
  _wt_copy_worktreeinclude "$root" "$dest"
  cd "$dest"
  _WT_HOOK_ROOT="$root" _wt_run_hook post-mk "$branch" "$dest"
  _wt_run_adhoc_hook "$post_hook" "$branch" "$dest"
}
