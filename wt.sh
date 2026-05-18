# resolve a worktree path by branch name or directory basename
_wt_resolve() {
  git worktree list --porcelain | awk -v q="$1" '
    /^worktree / { path = $2 }
    /^branch /   { branch = $2; sub("refs/heads/", "", branch) }
    /^$/         { if (branch == q || path ~ ("/" q "$")) { print path; exit } }
  '
}

# list branch names for all worktrees
_wt_branches() {
  git worktree list --porcelain 2>/dev/null | awk '
    /^branch / { sub("refs/heads/", "", $2); print $2 }
  '
}

# list all worktrees with their paths and branches
_wt_ls() {
  git worktree list
}

# navigate to a worktree by branch name or directory basename
_wt_cd() {
  local target
  target=$(_wt_resolve "${1?usage: wt <name>}")
  [ -z "$target" ] && { echo "wt: no worktree matching '$1'" >&2; return 1; }
  cd "$target"
}

# run a hook script from .wt-hooks/<event> if it exists and is executable
_wt_run_hook() {
  local event="$1"; shift
  local root="${_WT_HOOK_ROOT:-$(git rev-parse --show-toplevel)}"
  local hookfile="$root/.wt-hooks/$event"
  [ -x "$hookfile" ] || return 0
  WT_BRANCH="$1" WT_PATH="$2" "$hookfile"
}

# create a new worktree as a sibling of the current repo (optional explicit path as second arg)
_wt_mk() {
  local branch="${1?usage: wt mk <branch>}"
  local root; root=$(git rev-parse --show-toplevel)
  local safe="${branch//\//-}"
  local dest="${2:-$(dirname "$root")/$(basename "$root")-$safe}"
  _WT_HOOK_ROOT="$root" _wt_run_hook pre-mk "$branch" "$dest" || return
  git worktree add "$dest" -b "$branch" || return
  cd "$dest"
  _WT_HOOK_ROOT="$root" _wt_run_hook post-mk "$branch" "$dest"
}

# remove a worktree by branch name or directory basename
_wt_rm() {
  local root; root=$(git rev-parse --show-toplevel)
  local target
  target=$(_wt_resolve "${1?usage: wt rm <name>}")
  [ -z "$target" ] && { echo "wt: no worktree matching '$1'" >&2; return 1; }
  cd "$target"
  _WT_HOOK_ROOT="$root" _wt_run_hook pre-rm "$1" "$target" || { cd "$root"; return 1; }
  cd "$root"
  git worktree remove "$target"
  _WT_HOOK_ROOT="$root" _wt_run_hook post-rm "$1" "$target"
}

# prune stale worktree refs
_wt_prune() {
  git worktree prune -v
}

# show usage information
_wt_help() {
  cat <<'EOF'
Usage: wt [command] [args]

  wt                      list all worktrees
  wt <name>               cd into worktree by branch name
  wt mk <branch> [path]   create worktree (default: sibling of repo)
  wt rm <name>            remove a worktree
  wt prune                prune stale worktree refs
  wt ls                   list worktrees (same as bare wt)
  wt cd <name>            cd into worktree (explicit form)
  wt help                 show this help

Aliases: add=mk  remove=rm  list=ls

Hooks: place executable scripts in .wt-hooks/<event> at the repo root.
  Events: pre-mk, post-mk, pre-rm, post-rm
  Env vars passed: WT_BRANCH, WT_PATH
EOF
}

wt() {
  case "${1-}" in
    ''|ls|list)     _wt_ls ;;
    mk|add)         _wt_mk "${@:2}" ;;
    rm|remove)      _wt_rm "${@:2}" ;;
    prune)          _wt_prune ;;
    cd)             _wt_cd "${2?usage: wt cd <name>}" ;;
    help|--help|-h) _wt_help ;;
    *)              _wt_cd "$1" ;;
  esac
}

# --- completions ---

if [ -n "$ZSH_VERSION" ]; then
  _wt_complete() {
    local cur="${words[CURRENT]}"
    if [ $CURRENT -eq 2 ]; then
      local -a opts
      opts=(ls cd mk rm prune help $(_wt_branches))
      _describe 'option' opts
    elif [ $CURRENT -gt 2 ]; then
      case "${words[2]}" in
        rm|remove|cd)
          local -a branches
          branches=($(_wt_branches))
          _describe 'worktree' branches
          ;;
      esac
    fi
  }
  compdef _wt_complete wt

elif [ -n "$BASH_VERSION" ]; then
  _wt_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ $COMP_CWORD -eq 1 ]; then
      COMPREPLY=($(compgen -W "ls cd mk rm prune help $(_wt_branches)" -- "$cur"))
    else
      case "${COMP_WORDS[1]}" in
        rm|remove|cd)
          COMPREPLY=($(compgen -W "$(_wt_branches)" -- "$cur"))
          ;;
      esac
    fi
  }
  complete -F _wt_complete wt
fi
