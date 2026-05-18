# wt

A thin shell wrapper for `git worktree` with tab completion.

## Install

Add to your `~/.zshrc` or `~/.bashrc`:

```sh
source /path/to/wt-cli/wt.sh
```

Then reload your shell (`source ~/.zshrc`) or open a new terminal.

## Usage

```sh
wt                        # list all worktrees
wt <name>                 # cd into worktree by branch name
wt mk <branch>            # create worktree as sibling of current repo
wt mk <branch> <path>     # create worktree at a specific path
wt rm <name>              # remove a worktree
wt prune                  # prune stale worktree refs
wt ls                     # list worktrees (same as bare wt)
wt cd <name>              # explicit cd (same as wt <name>)
wt help                   # show usage
```

Aliases: `add` → `mk`, `remove` → `rm`, `list` → `ls`

Tab completion works for subcommands and branch names in both bash and zsh.

## Requirements

- git 2.5+
- bash or zsh

## Tests

Tests use [bats-core](https://github.com/bats-core/bats-core). Install it, then:

```sh
# Ubuntu/Debian
sudo apt install bats

# macOS
brew install bats-core
```

```sh
bats test/wt.bats
```
