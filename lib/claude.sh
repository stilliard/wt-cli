# resolve claude/jq/column to absolute paths up front and fetch the full
# session list once - sets _WT_CLAUDE_BIN / _WT_JQ_BIN / _WT_COLUMN_BIN /
# _WT_CLAUDE_JSON.
# Returns 0 on success, 1 if `claude` is missing (non-fatal, caller falls
# back to its normal output), 2 if `jq` is missing (fatal).
_wt_claude_init() {
  _WT_CLAUDE_BIN=$(command -v claude)
  if [ -z "$_WT_CLAUDE_BIN" ]; then
    echo "wt: claude CLI not found; ignoring --claude" >&2
    return 1
  fi
  _WT_JQ_BIN=$(command -v jq)
  if [ -z "$_WT_JQ_BIN" ]; then
    echo "wt: jq not found; --claude requires jq" >&2
    return 2
  fi
  _WT_COLUMN_BIN=$(command -v column)

  # fetch the full session list once and filter client-side
  # (`claude agents --cwd <path>` proved unreliable)
  _WT_CLAUDE_JSON=$("$_WT_CLAUDE_BIN" agents --json --all 2>/dev/null)
  # normalize a failed/malformed response to "[]"
  if ! printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" -e . >/dev/null 2>&1; then
    echo "wt: could not read Claude Code agent sessions; showing worktrees without session data" >&2
    _WT_CLAUDE_JSON="[]"
  fi

  # prefer the worktreePath recorded in Claude Code's job state over the
  # agents cwd, which is captured at dispatch time and often stale.
  # Best-effort: on any read/parse failure keep the agents data as-is.
  local jobs_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs" jobs_map enriched
  if [ -d "$jobs_dir" ]; then
    jobs_map=$(find "$jobs_dir" -mindepth 2 -maxdepth 2 -name state.json -exec cat {} + 2>/dev/null | "$_WT_JQ_BIN" -s \
      'map(select(.sessionId and .worktreePath) | {key: .sessionId, value: .worktreePath}) | from_entries' 2>/dev/null)
    if [ -n "$jobs_map" ] && [ "$jobs_map" != "{}" ]; then
      enriched=$(printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" --argjson jobs "$jobs_map" \
        'map(.cwd = ($jobs[.sessionId // ""] // .cwd))' 2>/dev/null)
      [ -n "$enriched" ] && _WT_CLAUDE_JSON="$enriched"
    fi
  fi
  return 0
}

# print a BRANCH/SESSION/NAME/STATE table for worktrees read as "path\tbranch"
# lines on stdin, using the state set by _wt_claude_init; worktrees with no
# session get a "-" placeholder row
_wt_claude_table() {
  # the main worktree's branch changes over time, so label it distinctly
  # rather than attributing sessions to whatever is checked out now
  local main_wt; main_wt=$(_wt_root)

  # NB: never name a shell variable "path" - zsh ties it to $PATH
  local wt_path branch display_branch sessions rows
  rows="BRANCH"$'\t'"SESSION"$'\t'"NAME"$'\t'"STATE"$'\n'
  while IFS=$'\t' read -r wt_path branch; do
    [ -z "$wt_path" ] && continue
    display_branch="$branch"
    [ "$wt_path" = "$main_wt" ] && display_branch="(main, branch varies)"
    sessions=$(printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" -r --arg wt "$wt_path" \
      '.[] | select(.cwd == $wt) | [.id, (.name // "-"), .state] | @tsv')
    if [ -z "$sessions" ]; then
      rows+="$display_branch"$'\t'"-"$'\t'"-"$'\t'"-"$'\n'
    else
      while IFS=$'\t' read -r id name state; do
        rows+="$display_branch"$'\t'"$id"$'\t'"$name"$'\t'"$state"$'\n'
      done <<< "$sessions"
    fi
  done

  if [ -n "$_WT_COLUMN_BIN" ]; then
    printf '%s' "$rows" | "$_WT_COLUMN_BIN" -t -s $'\t'
  else
    printf '%s' "$rows"
  fi
}

# delete the Claude Code sessions recorded against a worktree path (claude rm);
# expects _wt_claude_init to have been run already
_wt_claude_rm_sessions() {
  local wt_path="$1" rc=0 ids id
  ids=$(printf '%s' "$_WT_CLAUDE_JSON" | "$_WT_JQ_BIN" -r --arg wt "$wt_path" \
    '.[] | select(.cwd == $wt) | .id // empty')
  [ -z "$ids" ] && return 0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if "$_WT_CLAUDE_BIN" rm "$id" >/dev/null 2>&1; then
      echo "wt: deleted Claude session $id"
    else
      echo "wt: failed to delete Claude session $id" >&2
      rc=1
    fi
  done <<< "$ids"
  return "$rc"
}
