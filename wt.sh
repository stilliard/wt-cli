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

# resolve claude/jq/column to absolute paths up front and fetch the full
# session list once - sets _WT_CLAUDE_BIN / _WT_JQ_BIN / _WT_COLUMN_BIN /
# _WT_CLAUDE_JSON. Resolving up front lets callers preflight every
# dependency before doing anything destructive (see _wt_rm).
# Returns 0 on success, 1 if `claude` is missing (non-fatal, caller falls
# back to its normal output), 2 if `jq` is missing (fatal).
_wt_claude_init() {
  _WT_CLAUDE_BIN=$(command -v claude)
  if [ -z "$_WT_CLAUDE_BIN" ]; then
    echo "wt: claude CLI not found; ignoring --claude" >&2
    return 1
  fi
  _WT_JQ_BIN=$(command -v jq)
  if [ -z "$_WT_JQ_BIN" ]; then
    echo "wt: jq not found; --claude requires jq" >&2
    return 2
  fi
  _WT_COLUMN_BIN=$(command -v column)

  # fetch the full session list once and filter client-side
  # (`claude agents --cwd <path>` proved unreliable)
  _WT_CLAUDE_JSON=$("$_WT_CLAUDE_BIN" agents --json --all 2>/dev/null)
  # normalize a failed/malformed response to "[]"
  if ! printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" -e . >/dev/null 2>&1; then
    echo "wt: could not read Claude Code agent sessions; showing worktrees without session data" >&2
    _WT_CLAUDE_JSON="[]"
  fi

  # prefer the worktreePath recorded in Claude Code's job state over the
  # agents cwd, which is captured at dispatch time and often stale.
  # Best-effort: on any read/parse failure keep the agents data as-is.
  local jobs_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs" jobs_map enriched
  if [ -d "$jobs_dir" ]; then
    jobs_map=$(cat "$jobs_dir"/*/state.json 2>/dev/null | "$_WT_JQ_BIN" -s \
      'map(select(.sessionId and .worktreePath) | {key: .sessionId, value: .worktreePath}) | from_entries' 2>/dev/null)
    if [ -n "$jobs_map" ] && [ "$jobs_map" != "{}" ]; then
      enriched=$(printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" --argjson jobs "$jobs_map" \
        'map(.cwd = ($jobs[.sessionId // ""] // .cwd))' 2>/dev/null)
      [ -n "$enriched" ] && _WT_CLAUDE_JSON="$enriched"
    fi
  fi
  return 0
}

# print a BRANCH/SESSION/NAME/STATE table for worktrees read as "path\tbranch"
# lines on stdin, using the state set by _wt_claude_init; worktrees with no
# session get a "-" placeholder row
_wt_claude_table() {
  # the main worktree's branch changes over time, so label it distinctly
  # rather than attributing sessions to whatever is checked out now
  local main_wt
  main_wt=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')

  local wt_path branch display_branch sessions rows
  rows="BRANCH"$'\t'"SESSION"$'\t'"NAME"$'\t'"STATE"$'\n'
  while IFS=$'\t' read -r wt_path branch; do
    [ -z "$wt_path" ] && continue
    display_branch="$branch"
    [ "$wt_path" = "$main_wt" ] && display_branch="(main, branch varies)"
    sessions=$(printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" -r --arg wt "$wt_path" \
      '.[] | select(.cwd == $wt) | [.id, (.name // "-"), .state] | @tsv')
    if [ -z "$sessions" ]; then
      rows+="$display_branch"$'\t'"-"$'\t'"-"$'\t'"-"$'\n'
    else
      while IFS=$'\t' read -r id name state; do
        rows+="$display_branch"$'\t'"$id"$'\t'"$name"$'\t'"$state"$'\n'
      done <<< "$sessions"
    fi
  done

  if [ -n "$_WT_COLUMN_BIN" ]; then
    printf '%s' "$rows" | "$_WT_COLUMN_BIN" -t -s $'\t'
  else
    printf '%s' "$rows"
  fi
}

# delete the Claude Code sessions recorded against a worktree path (claude rm);
# expects _wt_claude_init to have been run already
_wt_claude_rm_sessions() {
  local wt_path="$1" rc=0 ids id
  ids=$(printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" -r --arg wt "$wt_path" \
    '.[] | select(.cwd == $wt) | .id // empty')
  [ -z "$ids" ] && return 0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if "$_WT_CLAUDE_BIN" rm "$id" >/dev/null 2>&1; then
      echo "wt: deleted Claude session $id"
    else
      echo "wt: failed to delete Claude session $id" >&2
      rc=1
    fi
  done <<< "$ids"
  return "$rc"
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

# run an ad-hoc hook script passed via --pre-hook / --post-hook
_wt_run_adhoc_hook() {
  local file="$1" branch="$2" wt_path="$3"
  [ -n "$file" ] || return 0
  [ -e "$file" ] || { echo "wt: hook file not found: $file" >&2; return 1; }
  if [ -x "$file" ]; then
    WT_BRANCH="$branch" WT_PATH="$wt_path" "$file"
  else
    WT_BRANCH="$branch" WT_PATH="$wt_path" bash "$file"
  fi
}

# copy files listed in .worktreeinclude (gitignore syntax) into a new worktree;
# only untracked, gitignored files are copied (Claude Code .worktreeinclude compatible)
_wt_copy_worktreeinclude() {
  local root="$1" dest="$2"
  local inc="$root/.worktreeinclude"
  [ -f "$inc" ] || return 0
  git -C "$root" ls-files -z --others --ignored --exclude-from="$inc" | while IFS= read -r -d '' rel; do
    [ -n "$rel" ] || continue
    git -C "$root" check-ignore -q -- "$rel" || continue
    mkdir -p "$dest/$(dirname "$rel")"
    cp -p "$root/$rel" "$dest/$rel"
  done
}

# create a new worktree as a sibling of the current repo (optional explicit path as second arg)
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
  local root; root=$(git rev-parse --show-toplevel)
  local safe="${branch//\//-}"
  local dest="${2:-$(dirname "$root")/$(basename "$root")-$safe}"
  _WT_HOOK_ROOT="$root" _wt_run_hook pre-mk "$branch" "$dest" || return
  _wt_run_adhoc_hook "$pre_hook" "$branch" "$dest" || return
  if [ -n "$base" ]; then
    git worktree add "$dest" -b "$branch" "$base" || return
  else
    git worktree add "$dest" -b "$branch" || return
  fi
  _wt_copy_worktreeinclude "$root" "$dest"
  cd "$dest"
  _WT_HOOK_ROOT="$root" _wt_run_hook post-mk "$branch" "$dest"
  _wt_run_adhoc_hook "$post_hook" "$branch" "$dest"
}

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
  local root; root=$(git rev-parse --show-toplevel)
  local target
  target=$(_wt_resolve "${1?usage: wt rm <name> [--claude] [--pre-hook P] [--post-hook P]}")
  [ -z "$target" ] && { echo "wt: no worktree matching '$1'" >&2; return 1; }
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
  # record the branch before removal so we can report it afterwards
  local wt_branch; wt_branch=$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null)
  git worktree remove "$target" || return $?
  echo "wt: removed $target${wt_branch:+ [$wt_branch]}"
  # removing a worktree never deletes its branch - say so, unless the caller
  # (wt merged --rm) is going to summarise for the whole batch
  if [ -n "$wt_branch" ] && [ "${_WT_RM_NO_HINT:-0}" -eq 0 ]; then
    echo "wt: branch '$wt_branch' is still here - delete it with: git branch -d $wt_branch"
  fi
  _WT_HOOK_ROOT="$root" _wt_run_hook post-rm "$1" "$target"
  _wt_run_adhoc_hook "$post_hook" "$1" "$target"
  if [ "$claude" -eq 1 ]; then
    _wt_claude_rm_sessions "$target" || rc=1
  fi
  return "$rc"
}

# prune stale worktree refs
_wt_prune() {
  git worktree prune -v
}

# true if a branch has any commits past the point it was branched from.
# The oldest reflog entry records that point; with no reflog we can't tell,
# so assume yes.
_wt_branch_has_commits() {
  local branch="$1" created
  created=$(git reflog show --format=%H "$branch" 2>/dev/null)
  created=${created##*$'\n'}   # oldest entry is the last line
  [ -z "$created" ] && return 0
  [ "$(git rev-list --count "$created..$branch" 2>/dev/null)" != "0" ]
}

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

  # a branch with no commits of its own only looks merged because it never
  # moved off the commit it was branched from
  local filtered="" wt_path branch
  while IFS=$'\t' read -r wt_path branch; do
    [ -z "$wt_path" ] && continue
    _wt_branch_has_commits "$branch" || continue
    filtered+="$wt_path	$branch"$'\n'
  done <<< "$list"
  list=${filtered%$'\n'}
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
  # wt_path/branch are already local to this function (declared above); zsh
  # prints a re-declared local, so only introduce the new names here
  local main_wt failed=0 removed=""
  main_wt=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
  while IFS=$'\t' read -r wt_path branch; do
    [ -z "$wt_path" ] && continue
    if [ "$wt_path" = "$main_wt" ]; then
      echo "wt: skipping main worktree [$branch]" >&2
      continue
    fi
    if [ "$show_claude" -eq 1 ]; then
      _WT_RM_NO_HINT=1 _wt_rm --claude "$branch" || { failed=1; continue; }
    else
      _WT_RM_NO_HINT=1 _wt_rm "$branch" || { failed=1; continue; }
    fi
    removed+=" $branch"
  done <<< "$list"
  # one hint for the batch rather than one per worktree
  [ -n "$removed" ] && echo "wt: branches are still here - delete them with: git branch -d$removed"
  [ "$failed" -eq 0 ]
}

# show usage information
_wt_help() {
  cat <<'EOF'
Usage: wt [command] [args]

Commands:
  wt                            list all worktrees
  wt <name>                     cd into worktree by branch name
  wt cd <name>                  cd into worktree (explicit form)
  wt ls [opts]                  list worktrees (same as bare wt)
  wt mk <branch> [path] [opts]  create worktree (default: sibling of repo)
  wt rm <name> [opts]           remove a worktree
  wt prune                      prune stale worktree refs
  wt merged [base] [opts]       list worktrees merged into base (default: main/master)
  wt help                       show this help

Aliases: add=mk, remove=rm, list=ls

Options (ls|merged):
  --claude          show a table of Claude Code agent sessions per worktree

Options (merged):
  --rm              remove the listed worktrees; with --claude, also delete
                     their Claude Code sessions. Branches are always kept.
  -y, --yes         skip the confirmation prompt

Options (mk):
  --base BRANCH     create the new branch from this commit-ish (default: HEAD)
  --pre-hook PATH   run a script before the action (non-zero exit aborts)
  --post-hook PATH  run a script after the action

Options (rm):
  --claude          also delete the worktree's Claude Code sessions
  --pre-hook PATH   run a script before the action (non-zero exit aborts)
  --post-hook PATH  run a script after the action

Hooks:
  Place executable scripts in .wt-hooks/<event> at the repo root.
  Events: pre-mk, post-mk, pre-rm, post-rm
  Hook scripts receive WT_BRANCH and WT_PATH env vars.

.worktreeinclude:
  List gitignored paths (gitignore syntax) at the repo root to copy
  them into each new worktree. Compatible with Claude Code.
EOF
}

wt() {
  case "${1-}" in
    ''|ls|list)     _wt_ls "${@:2}" ;;
    mk|add)         _wt_mk "${@:2}" ;;
    rm|remove)      _wt_rm "${@:2}" ;;
    prune)          _wt_prune ;;
    merged)         _wt_merged "${@:2}" ;;
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
      opts=(ls cd mk rm prune merged help $(_wt_branches))
      _describe 'option' opts
    elif [ $CURRENT -gt 2 ]; then
      case "${words[2]}" in
        rm|remove|cd|merged)
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
      COMPREPLY=($(compgen -W "ls cd mk rm prune merged help $(_wt_branches)" -- "$cur"))
    else
      case "${COMP_WORDS[1]}" in
        rm|remove|cd|merged)
          COMPREPLY=($(compgen -W "$(_wt_branches)" -- "$cur"))
          ;;
      esac
    fi
  }
  complete -F _wt_complete wt
fi
