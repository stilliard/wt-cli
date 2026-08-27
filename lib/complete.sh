# filter candidates ($2...) against the typed word ($1): prefix matches, else substring
_wt_match() {
  local cur="$1" name pre="" sub=""
  shift
  for name in "$@"; do
    case "$name" in
      "$cur"*)  pre="$pre$name
" ;;
      *"$cur"*) sub="$sub$name
" ;;
    esac
  done
  [ -n "$pre" ] && printf '%s' "$pre" || printf '%s' "$sub"
}

if [ -n "$ZSH_VERSION" ]; then
  _wt_complete() {
    local cur="${words[CURRENT]}"
    local -a matches
    # l:|=* matches the typed text anywhere in a candidate
    if [ $CURRENT -eq 2 ]; then
      matches=(ls cd code mk rm prune merged root help $(_wt_branches))
      compadd -M 'l:|=*' -a matches
    elif [ $CURRENT -gt 2 ]; then
      case "${words[2]}" in
        cd|code)
          matches=(root $(_wt_branches))
          compadd -M 'l:|=*' -a matches
          ;;
        rm|remove|del|merged)
          matches=($(_wt_branches))
          compadd -M 'l:|=*' -a matches
          ;;
      esac
    fi
  }
  compdef _wt_complete wt

elif [ -n "$BASH_VERSION" ]; then
  # fill COMPREPLY with the candidates ($2...) matching the typed word ($1)
  _wt_compreply() {
    local cur="$1"
    shift
    COMPREPLY=($(_wt_match "$cur" "$@"))
    # readline overwrites the word with the matches' common prefix, so only
    # complete an ambiguous set when it shares the typed prefix
    if [ ${#COMPREPLY[@]} -gt 1 ] && [ -n "$cur" ]; then
      case "${COMPREPLY[0]}" in
        "$cur"*) ;;
        *) COMPREPLY=() ;;
      esac
    fi
  }

  _wt_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ $COMP_CWORD -eq 1 ]; then
      _wt_compreply "$cur" ls cd code mk rm prune merged root help $(_wt_branches)
    else
      case "${COMP_WORDS[1]}" in
        cd|code)
          _wt_compreply "$cur" root $(_wt_branches)
          ;;
        rm|remove|del|merged)
          _wt_compreply "$cur" $(_wt_branches)
          ;;
      esac
    fi
  }
  complete -F _wt_complete wt
fi
