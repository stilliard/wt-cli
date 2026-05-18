# wt

A thin shell wrapper for `git worktree` with tab completion.

## Install

Clone the repo (or just download `wt.sh`) to wherever you'd like, `~/.wt-cli` is an example of where you could put it:

```sh
git clone https://github.com/stilliard/wt-cli.git ~/.wt-cli
```

Then add to your `~/.zshrc` or `~/.bashrc`, adjusting the path to match where you saved it:

```sh
source ~/.wt-cli/wt.sh
```

Then reload your shell (`source ~/.zshrc`) or open a new terminal.

## Usage

```sh
wt                        # list all worktrees
wt <name>                 # cd into worktree by branch name
wt mk <branch>            # create worktree as sibling of current repo and cd into it
wt mk <branch> <path>     # create worktree at a specific path and cd into it
wt rm <name>              # remove a worktree
wt prune                  # prune stale worktree refs
wt ls                     # list worktrees (same as bare wt)
wt cd <name>              # explicit cd (same as wt <name>)
wt help                   # show usage
```

Aliases: `add` → `mk`, `remove` → `rm`, `list` → `ls`

Tab completion works for subcommands and branch names in both bash and zsh.

## Hooks

Place executable scripts in `.wt-hooks/<event>` at your repo root to run custom logic around worktree operations.

| Event | When | Runs in |
|-------|------|---------|
| `pre-mk` | Before creating a worktree (non-zero exit aborts) | Original repo |
| `post-mk` | After creating a worktree | New worktree |
| `pre-rm` | Before removing a worktree (non-zero exit aborts) | Worktree being removed |
| `post-rm` | After removing a worktree | Original repo |

Each hook receives the branch name and path via env vars `WT_BRANCH` and `WT_PATH`. The standard `OLDPWD` is also available, pointing to the directory you were in before the worktree was created.

**Example** - copy env and install dependencies after creating a worktree:

```sh
#!/bin/sh
# .wt-hooks/post-mk  (runs inside the new worktree)
cp "$OLDPWD/.env" .env
npm install
```

```sh
chmod +x .wt-hooks/post-mk
```

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

## License

[MIT](LICENSE)
