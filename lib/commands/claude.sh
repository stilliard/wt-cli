# open a Claude Code session for a worktree (the shared session-list helpers
# live in lib/claude.sh). By default it resumes the most recent session recorded
# against that worktree, falling back to a fresh one; --new always starts fresh.
# With no name it uses the worktree you are standing in.
# Runs in a subshell, so the caller's shell stays where it was, like `wt code`.
_wt_claude_cmd() {
  # an optional worktree name comes first (--new may lead it), and everything
  # from the first claude flag on is passed through untouched. wt can't know
  # which of claude's own flags take a value, so it never looks for a name
  # past one: `wt claude --effort high` means the current worktree, not "high".
  local name="" new=""
  local args; args=()
  while [ "$#" -gt 0 ] && [ -z "$name" ]; do
    case "$1" in
      --new) new=1 ;;
      -*)    break ;;
      *)     name="$1" ;;
    esac
    shift
  done

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --new) new=1 ;;
      --)    shift; args+=("$@"); break ;;
      *)     args+=("$1") ;;
    esac
    shift
  done

  local target
  target=$(_wt_target_here "$name" "wt claude <name>") || return 1

  local claude_bin; claude_bin=$(command -v claude)
  if [ -z "$claude_bin" ]; then
    echo "wt: claude CLI not found" >&2
    return 1
  fi

  if [ -n "$new" ]; then
    (cd "$target" && "$claude_bin" "${args[@]}")
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "wt: jq not found; resuming a session requires jq (use --new to skip the lookup)" >&2
    return 1
  fi
  _wt_claude_init || return 1
  # a lookup that failed leaves an empty list behind; starting a fresh session
  # off the back of that would quietly strand (or duplicate) a real one
  if [ -n "$_WT_CLAUDE_DEGRADED" ]; then
    echo "wt: not starting a session without knowing what is already there (use --new to start one anyway)" >&2
    return 1
  fi

  # newest session recorded against this worktree, if any
  local sid
  sid=$(printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" -r --arg wt "$target" \
    '[.[] | select(.cwd == $wt) | select((.sessionId // "") != "")]
       | sort_by(.startedAt // 0) | last | .sessionId // empty')

  if [ -z "$sid" ]; then
    echo "wt: no Claude session found for $target; starting a new one"
    (cd "$target" && "$claude_bin" "${args[@]}")
  else
    echo "wt: resuming Claude session $sid"
    (cd "$target" && "$claude_bin" --resume "$sid" "${args[@]}")
  fi
}
