# wt

A thin shell wrapper for `git worktree` with tab completion. Plays well with [Claude Code](https://claude.com/claude-code): worktrees it creates for background agents (`.claude/worktrees/…`) show up in `wt ls`/`wt merged` like any other, `.worktreeinclude` uses the same format Claude Code reads for `claude --worktree`, and `--claude` cross-references `wt`'s worktree list against `claude agents` to show each branch's session id/name/state — see [Claude Code integration](#claude-code-integration) below.

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
wt merged                 # list worktrees whose branch is merged into main/master
wt ls                     # list worktrees (same as bare wt)
wt ls --claude            # list worktrees with their Claude Code agent sessions
wt merged --claude        # merged-worktree candidates, with their Claude Code agent sessions
wt merged --rm            # remove all merged worktrees (asks first; -y to skip)
wt rm <name> --claude     # remove a worktree and delete its Claude Code sessions
wt cd <name>              # explicit cd (same as wt <name>)
wt help                   # show usage
```

Aliases: `add` → `mk`, `remove` → `rm`, `list` → `ls`

Tab completion works for subcommands and branch names in both bash and zsh, matching anywhere in the branch name (`wt api-webhook<TAB>` → `worktree-api-webhook-error-alerts`).

`wt merged` detects `main` or `master` automatically, or pass an explicit base: `wt merged develop`. It only lists candidates — run `wt rm <name>` yourself to remove them. (`wt prune` is unrelated: it just cleans up `git worktree` metadata for directories that were deleted outside of `wt rm`.)

## Claude Code integration

`wt ls` and `wt merged` both accept `--claude`, which cross-references your worktrees against `claude agents --json --all` and prints a table of each worktree's branch, session id, name, and state:

```
$ wt merged --claude
BRANCH                           SESSION   NAME                                STATE
worktree-charge-types-api        82c265b2  charge api resource investigation   done
worktree-dropship-restrictions   5016d5c3  dropship feature cond. visibility   blocked
worktree-product-types-api       -         -                                   -
```

Worktrees with no known session get a `-` placeholder row — handy for spotting merged branches that are safe to `wt rm`. Sessions that ran directly in your main repo checkout (rather than a dedicated worktree) are grouped under `(main, branch varies)`, since the main checkout's branch changes over time.

To clean up, `wt merged --rm` removes everything `wt merged` lists (never the main worktree), and adding `--claude` also deletes each worktree's Claude Code sessions via `claude rm`. It shows the list and asks for confirmation first — pass `-y` to skip. For a single worktree, `wt rm <name> --claude` removes the worktree and deletes its sessions.

Requires `jq`.

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

### Ad-hoc hooks for testing

`wt mk` and `wt rm` also accept `--pre-hook PATH` and `--post-hook PATH` flags to run a single script for one invocation, without committing it to `.wt-hooks/`. The script receives the same `WT_BRANCH` / `WT_PATH` env vars; a failing `--pre-hook` aborts the operation.

```sh
wt mk feature-x --post-hook ./my-setup.sh
wt rm feature-x --pre-hook  ./my-teardown.sh
```

## Copying gitignored files into new worktrees

A new worktree is a fresh checkout, so untracked files like `.env` are not present in it. List the paths you want carried over in a `.worktreeinclude` file at your repo root, using `.gitignore` syntax:

```text
# .worktreeinclude
.env
.env.local
.claude/settings.local.json
```

On `wt mk`, any file that matches a pattern **and** is gitignored is copied into the new worktree. Tracked files are never duplicated. This is the same file Claude Code uses for `claude --worktree`, so one config serves both tools.

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

Tests are split one file per command (`test/*.bats`), with `--claude`-flag tests grouped under `test/claude/`. Run the whole suite with `-r` (recursive):

```sh
bats -r test
```

## License

[MIT](LICENSE)
