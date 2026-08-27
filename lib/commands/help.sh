# show usage information
_wt_help() {
  cat <<'EOF'
Usage: wt [command] [args]

Commands:
  wt                            list all worktrees
  wt <name>                     cd into worktree by branch name
  wt ~                          cd to the repo root (also: wt root)
  wt cd <name>                  cd into worktree (explicit form)
  wt ls [opts]                  list worktrees (same as bare wt)
  wt mk <branch> [path] [opts]  create worktree (default: .claude/worktrees/<branch>)
  wt rm <name> [opts]           remove a worktree, offering to delete its branch
  wt prune                      prune stale worktree refs
  wt merged [base] [opts]       list worktrees merged into base (default: main/master)
  wt help                       show this help

Aliases: add/create=mk, remove/del=rm, list=ls

Options (ls|merged):
  --claude          show a table of Claude Code agent sessions per worktree

Options (merged):
  --rm              remove the listed worktrees; with --claude, also delete
                     their Claude Code sessions
  -y, --yes         answer yes to the prompts (worktrees and their branches)

Options (mk):
  --base BRANCH     create the new branch from this commit-ish (default: HEAD)
                     without it, an existing local or origin branch is reused
  --pre-hook PATH   run a script before the action (non-zero exit aborts)
  --post-hook PATH  run a script after the action

Options (rm):
  --claude          also delete the worktree's Claude Code sessions
  -y, --yes         answer yes to the "also delete branch?" prompt
  --pre-hook PATH   run a script before the action (non-zero exit aborts)
  --post-hook PATH  run a script after the action

Hooks:
  Place executable scripts in .wt-hooks/<event> at the repo root.
  Events: pre-mk, post-mk, pre-rm, post-rm
  Hook scripts receive WT_BRANCH, WT_PATH and WT_ROOT env vars.

wt.path:
  Where `wt mk` puts a worktree, if you don't want .claude/worktrees/<branch>:
    git config wt.path '../{repo}-{name}'      # sibling of the repo
    git config --global wt.path '~/wt/{name}'  # all repos, outside the tree
  {name} is the branch with slashes replaced and a leading worktree- dropped,
  {repo} the repo's folder name.
  A relative template resolves against the repo root.

.worktreeinclude:
  List gitignored paths (gitignore syntax) at the repo root to copy
  them into each new worktree. Compatible with Claude Code.
EOF
}

