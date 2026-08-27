# open a worktree in an editor - VS Code by default, or whatever `wt.editor` is
# set to. The editor is run in the foreground, which is right either way: a GUI
# editor like `code` returns straight away, a terminal one like `vim` shouldn't.
_wt_code() {
  local target editor
  target=$(_wt_target "${1?usage: wt code <name>}") || return 1
  editor=$(git config wt.editor) || editor=code
  [ -n "$editor" ] || editor=code
  # split into command + arguments, so wt.editor can carry flags and quoted
  # paths ('code -n'). eval is how git runs core.editor and ! aliases too, and
  # this is the user's own config: never cloned, no less trusted than either.
  eval "set -- $editor" 2>/dev/null || {
    echo "wt: could not parse wt.editor '$editor' as a command" >&2
    return 1
  }
  [ "$#" -gt 0 ] && command -v "$1" >/dev/null 2>&1 || {
    echo "wt: editor '$editor' not found; set one with: git config wt.editor <cmd>" >&2
    return 1
  }
  "$@" "$target"
}
