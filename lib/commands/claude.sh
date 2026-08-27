# resume the most recent Claude Code session recorded against a worktree, or
# start a fresh one (always, with --new). With no name it uses the worktree you
# are standing in, and runs in a subshell so the caller's shell stays put.
_wt_claude_cmd() {
  # wt can't know which of claude's own flags take a value, so it stops looking
  # for a name at the first flag: `wt claude --effort high` means the current
  # worktree, not one called "high". Everything but --new goes to claude.
  local name="" new="" seen_flag=""
  local args; args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --new) new=1 ;;
      --)    shift; args+=("$@"); break ;;
      -*)    seen_flag=1; args+=("$1") ;;
      *)     if [ -z "$name" ] && [ -z "$seen_flag" ]; then name="$1"; else args+=("$1"); fi ;;
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
  # a failed lookup leaves an empty list behind, which would look like "no
  # session here" and strand a real one behind a new session
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
