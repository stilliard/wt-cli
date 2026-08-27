# wt

A thin shell wrapper for `git worktree` with tab completion. Plays well with [Claude Code](https://claude.com/claude-code): worktrees it creates for background agents (`.claude/worktrees/…`) show up in `wt ls`/`wt merged` like any other, `.worktreeinclude` uses the same format Claude Code reads for `claude --worktree`, `--claude` cross-references `wt`'s worktree list against `claude agents` to show each branch's session id/name/state, and `wt claude <branch>` resumes a worktree's session — see [Claude Code integration](#claude-code-integration) below.

## Install

Clone the repo to wherever you'd like, `~/.wt-cli` is an example of where you could put it:

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
wt ~                      # cd to the repo root (also: wt root)
wt mk <branch>            # create worktree in .claude/worktrees/<branch> and cd into it
wt mk <branch> <path>     # create worktree at a specific path and cd into it
wt rm <name>              # remove a worktree
wt prune                  # prune stale worktree refs
wt merged                 # list worktrees whose branch is merged into main/master
wt ls                     # list worktrees (same as bare wt)
wt ls --claude            # list worktrees with their Claude Code agent sessions
wt merged --claude        # merged-worktree candidates, with their Claude Code agent sessions
wt merged --rm            # remove all merged worktrees (asks first; -y to skip)
wt rm <name> --claude     # remove a worktree and delete its Claude Code sessions
wt rm <name> -y           # remove a worktree and its branch, no prompt
wt cd <name>              # explicit cd (same as wt <name>)
wt code <name>            # open a worktree in VS Code
wt claude <name>          # resume the worktree's Claude Code session (or start one)
wt claude <name> --new    # always start a new session there
wt help                   # show usage
```

Aliases: `add`/`create` → `mk`, `remove`/`del` → `rm`, `list` → `ls`

Worktrees are created in `.claude/worktrees/<branch>` inside the repo, the same place Claude Code puts them, so both tools see the same set. Add `.claude/worktrees/` to your `.gitignore` if it isn't already. Slashes in a branch name become dashes in the folder, and a leading `worktree-` is dropped (Claude Code names its branches that way, so `wt mk worktree-my-feature` creates `.claude/worktrees/my-feature`, matching what Claude Code would do).

Set `wt.path` to put them somewhere else - `{name}` is the branch with slashes replaced, `{repo}` the repo's folder name, and a relative template resolves against the repo root so it means the same from any worktree:

```sh
git config wt.path '../{repo}-{name}'      # sibling of the repo
git config --global wt.path '~/wt/{name}'  # all repos, outside the tree
```

`wt code <name>` opens a worktree in your editor without cd-ing into it, resolving the name the same way `wt cd` does (so `wt code ~` opens the repo root). It runs `code` by default; set `wt.editor` for anything else:

```sh
git config --global wt.editor cursor
git config --global wt.editor 'code -n'    # flags and quoted paths are fine
```

Like any subcommand, `code` and `claude` shadow a branch of the same name - if you have one, `wt cd code` still reaches it.

`wt mk` reuses an existing branch where there is one - a local branch is checked out as is, and a branch that only exists on `origin` gets a local tracking branch. Otherwise the branch is created, from `--base` if given.

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

Removing a worktree leaves its branch behind, so both commands then offer to delete the branches too (`wt rm` asks about the one branch, `wt merged --rm` asks once for the batch). Deletion always goes through `git branch -d`, never `-D`, so an unmerged branch is refused and reported rather than lost. `-y` answers yes to every prompt, worktrees and branches alike; with nothing on stdin to answer with the prompt goes unanswered and the branch is kept, so non-interactive callers are unaffected.

`wt claude <name>` picks up where an agent left off: it looks for the Claude Code sessions recorded against that worktree, resumes the most recent one with `claude --resume`, and starts a fresh session if there is none. It runs `claude` in the worktree without cd-ing your shell into it, resolving the name the same way `wt cd` does.

```sh
wt claude api-webhook           # resume the newest session for that worktree
wt claude api-webhook --new     # skip the lookup, start fresh
wt claude api-webhook --effort high   # anything else is passed through to claude
```

Sessions are matched to worktrees the same way `--claude` matches them, so a background agent whose recorded `cwd` is stale is still found. `--new` needs neither `jq` nor a session lookup.

Requires `jq` (except for `wt claude --new`).

## Hooks

Place executable scripts in `.wt-hooks/<event>` at your repo root to run custom logic around worktree operations.

| Event | When | Runs in |
|-------|------|---------|
| `pre-mk` | Before creating a worktree (non-zero exit aborts) | Original repo |
| `post-mk` | After creating a worktree | New worktree |
| `pre-rm` | Before removing a worktree (non-zero exit aborts) | Worktree being removed |
| `post-rm` | After removing a worktree | Original repo |

Each hook receives the branch name and path via env vars `WT_BRANCH` and `WT_PATH`, plus the main worktree's root as `WT_ROOT` (useful for calling a setup script that lives in the repo). The standard `OLDPWD` is also available, pointing to the directory you were in before the worktree was created.

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
