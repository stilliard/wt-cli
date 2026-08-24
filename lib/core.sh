# the main worktree's root, even when called from inside a linked worktree
# (--git-common-dir is relative to cwd in the main worktree, absolute in a linked one)
_wt_root() {
  local common; common=$(git rev-parse --git-common-dir) || return 1
  (cd "$(dirname "$common")" && pwd)
}

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

# run a hook script from .wt-hooks/<event> if it exists and is executable
_wt_run_hook() {
  local event="$1"; shift
  local root="${_WT_HOOK_ROOT:-$(_wt_root)}"
  local hookfile="$root/.wt-hooks/$event"
  [ -x "$hookfile" ] || return 0
  WT_BRANCH="$1" WT_PATH="$2" WT_ROOT="$root" "$hookfile"
}

# run an ad-hoc hook script passed via --pre-hook / --post-hook
_wt_run_adhoc_hook() {
  local file="$1" branch="$2" wt_path="$3"
  [ -n "$file" ] || return 0
  [ -e "$file" ] || { echo "wt: hook file not found: $file" >&2; return 1; }
  local root="${_WT_HOOK_ROOT:-$(_wt_root)}"
  if [ -x "$file" ]; then
    WT_BRANCH="$branch" WT_PATH="$wt_path" WT_ROOT="$root" "$file"
  else
    WT_BRANCH="$branch" WT_PATH="$wt_path" WT_ROOT="$root" bash "$file"
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

# where a new worktree goes: the wt.path template if set, else .claude/worktrees/<name>.
# {name} is the branch with slashes replaced, {repo} the repo's folder name. A relative
# template resolves against the repo root, so it means the same from any worktree.
_wt_dest_default() {
  local root="$1" safe="$2" tmpl
  tmpl=$(git -C "$root" config wt.path) || tmpl='.claude/worktrees/{name}'
  case "$tmpl" in
    *'{name}'*) ;;
    *) echo "wt: wt.path must contain {name}, got '$tmpl'" >&2; return 1 ;;
  esac
  tmpl=${tmpl//\{name\}/$safe}
  tmpl=${tmpl//\{repo\}/$(basename "$root")}
  case "$tmpl" in
    "~/"*) printf '%s' "$HOME/${tmpl#\~/}" ;;
    /*)    printf '%s' "$tmpl" ;;
    *)     printf '%s/%s' "$root" "$tmpl" ;;
  esac
}

# collapse . and .. in a path textually - the target may not exist yet, so this can't
# go via realpath/cd. Avoids IFS word splitting, which zsh doesn't do by default.
_wt_normpath() {
  local rest="$1" out="" seg lead=""
  case "$rest" in /*) lead="/" ;; esac
  while [ -n "$rest" ]; do
    seg="${rest%%/*}"
    if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
    case "$seg" in
      ''|.) ;;
      ..)   out="${out%/*}" ;;
      *)    out="$out/$seg" ;;
    esac
  done
  printf '%s' "$lead${out#/}"
}

# warn when a worktree inside the repo isn't gitignored, so it doesn't show up as
# untracked in every git status from now on
_wt_warn_unignored() {
  local root="$1" dest; dest=$(_wt_normpath "$2")
  case "$dest" in "$root"/*) ;; *) return 0 ;; esac
  local rel="${dest#"$root"/}" rc=0
  git -C "$root" check-ignore -q "$rel" || rc=$?
  # 0 ignored, 1 not ignored, anything else is an error we shouldn't report as "not ignored"
  [ "$rc" -eq 1 ] || return 0
  echo "wt: $rel is not gitignored; add it to .gitignore to keep git status clean" >&2
}
