# wt - a thin shell wrapper for git worktree. Source this file from your
# ~/.zshrc or ~/.bashrc; it loads the rest of the tool from lib/ alongside it.

if [ -n "$BASH_VERSION" ]; then
  _WT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
else
  _WT_DIR=$(cd "$(dirname "${(%):-%x}")" && pwd)  # zsh
fi

. "$_WT_DIR/lib/core.sh"
. "$_WT_DIR/lib/claude.sh"
. "$_WT_DIR/lib/commands/ls.sh"
. "$_WT_DIR/lib/commands/cd.sh"
. "$_WT_DIR/lib/commands/code.sh"
. "$_WT_DIR/lib/commands/claude.sh"
. "$_WT_DIR/lib/commands/mk.sh"
. "$_WT_DIR/lib/commands/rm.sh"
. "$_WT_DIR/lib/commands/prune.sh"
. "$_WT_DIR/lib/commands/merged.sh"
. "$_WT_DIR/lib/commands/help.sh"
. "$_WT_DIR/lib/complete.sh"

wt() {
  case "${1-}" in
    ''|ls|list)     _wt_ls "${@:2}" ;;
    mk|add|create)  _wt_mk "${@:2}" ;;
    rm|remove|del)  _wt_rm "${@:2}" ;;
    prune)          _wt_prune ;;
    merged)         _wt_merged "${@:2}" ;;
    cd)             _wt_cd "${2?usage: wt cd <name>}" ;;
    code)           _wt_code "${2-}" ;;
    claude)         _wt_claude_cmd "${@:2}" ;;
    help|--help|-h) _wt_help ;;
    *)              _wt_cd "$1" ;;
  esac
}
