# Start configuration added by Zim Framework install {{{
#
# User configuration sourced by interactive shells
#

# -----------------
# Zsh configuration
# -----------------

#
# History
#

# Remove older command from the history if a duplicate is to be added.
setopt HIST_IGNORE_ALL_DUPS

#
# Input/output
#

# Set editor default keymap to emacs (`-e`) or vi (`-v`)
bindkey -v

# Prompt for spelling correction of commands.
#setopt CORRECT

# Customize spelling correction prompt.
#SPROMPT='zsh: correct %F{red}%R%f to %F{green}%r%f [nyae]? '

# Remove path separator from WORDCHARS.
WORDCHARS=${WORDCHARS//[\/]}

# --------------------
# Module configuration
# --------------------

#
# git
#

# Set a custom prefix for the generated aliases. The default prefix is 'G'.
#zstyle ':zim:git' aliases-prefix 'g'

#
# input
#

# Append `../` to your input for each `.` you type after an initial `..`
#zstyle ':zim:input' double-dot-expand yes

#
# termtitle
#

# Set a custom terminal title format using prompt expansion escape sequences.
# See http://zsh.sourceforge.net/Doc/Release/Prompt-Expansion.html#Simple-Prompt-Escapes
# If none is provided, the default '%n@%m: %~' is used.
#zstyle ':zim:termtitle' format '%1~'

#
# zsh-autosuggestions
#

# Disable automatic widget re-binding on each precmd. This can be set when
# zsh-users/zsh-autosuggestions is the last module in your ~/.zimrc.
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

# Customize the style that the suggestions are shown with.
# See https://github.com/zsh-users/zsh-autosuggestions/blob/master/README.md#suggestion-highlight-style
#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'

#
# zsh-syntax-highlighting
#

# Set what highlighters will be used.
# See https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters.md
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

# Customize the main highlighter styles.
# See https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters/main.md#how-to-tweak-it
#typeset -A ZSH_HIGHLIGHT_STYLES
#ZSH_HIGHLIGHT_STYLES[comment]='fg=242'

# ------------------
# Initialize modules
# ------------------

# own completions (e.g. _list for list/kindle); must be on fpath before Zim runs compinit
fpath=(~/.zfunc $fpath)
ZIM_HOME=${ZDOTDIR:-${HOME}}/.zim
# Download zimfw plugin manager if missing.
if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
  if (( ${+commands[curl]} )); then
    curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
        https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  else
    mkdir -p ${ZIM_HOME} && wget -nv -O ${ZIM_HOME}/zimfw.zsh \
        https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  fi
fi
# Install missing modules, and update ${ZIM_HOME}/init.zsh if missing or outdated.
if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZIM_CONFIG_FILE:-${ZDOTDIR:-${HOME}}/.zimrc} ]]; then
  source ${ZIM_HOME}/zimfw.zsh init
fi
# Initialize modules.
source ${ZIM_HOME}/init.zsh
# }}} End configuration added by Zim Framework install

# -----------------
# User configuration
# -----------------

HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=${HISTSIZE:-10000}
SAVEHIST=${SAVEHIST:-10000}
setopt HIST_REDUCE_BLANKS

export LANG=en_US.UTF-8
export EDITOR=${EDITOR:-nvim}
export VISUAL=${VISUAL:-$EDITOR}
export LESS=${LESS:--R}

# Aliases
alias api='curl https://openrouter.ai/api/v1/credits \
     -H "Authorization: Bearer $OPENROUTER_API_KEY"'
alias deepl='curl -X GET "https://api.deepl.com/v2/usage" \
     -H "Authorization: DeepL-Auth-Key $DEEPL_API_KEY" | jq'
alias vim="nvim"
alias f="fastfetch"
alias t="taskwarrior-tui"

alias typora='open -a Typora'
alias zathura='zathura --plugins-dir /opt/homebrew/lib/zathura'


# Functions
ss() {
  query=$(echo "$@" | tr ' ' '+')
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $@" >> ~/Notes/Queries_Log.md
  open -a Safari "https://www.google.com/search?q=$query"
}

function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# function t() {
#   local db=~/Library/Group\ Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-XP5VV/Things\ Database.thingsdatabase/main.sqlite
#   local y=$(date +%Y)
#   local m=$(date +%-m)
#   local d=$(date +%-d)
#   local encoded=$(( (y << 16) | (m << 12) | (d << 7) ))
#   sqlite3 "$db" "SELECT ROW_NUMBER() OVER() || '. ' || title FROM TMTask WHERE trashed = 0 AND status = 0 AND type = 0 AND startDate IS NOT NULL AND startDate <= $encoded;"
# }

function d() {
  local db=~/Library/Group\ Containers/JLMPQHK86H.com.culturedcode.ThingsMac/ThingsData-XP5VV/Things\ Database.thingsdatabase/main.sqlite
  local token="$THINGS_AUTH_TOKEN"
  local y=$(date +%Y)
  local m=$(date +%-m)
  local d=$(date +%-d)
  local encoded=$(( (y << 16) | (m << 12) | (d << 7) ))
  local result=$(sqlite3 "$db" "SELECT uuid, title FROM TMTask WHERE trashed = 0 AND status = 0 AND type = 0 AND startDate IS NOT NULL AND startDate <= $encoded LIMIT 1 OFFSET $(($1 - 1));")
  local uuid=$(echo "$result" | cut -d'|' -f1)
  local title=$(echo "$result" | cut -d'|' -f2)

  if [ -z "$uuid" ]; then
    echo "No task at number: $1"
    return 1
  fi

  open "things:///update?auth-token=$token&id=$uuid&completed=true"
  echo "Completed: $title"
}

# kagi search 
ks() {
  if [[ -z "$1" ]]; then
    echo "usage: ks <query>" >&2
    return 1
  fi

  curl -s https://kagi.com/api/v1/search \
    -H "Authorization: Bearer $KAGI_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$(jq -n --arg q "$*" '{query: $q}')" |
  jq -r '
    .data.search
    | map(select(.props.ai_generated != true))
    | .[:5][]
    | "\u001b[1m\(.title)\u001b[0m\n\(.url)\n\(.snippet // "" | gsub("\\s+"; " "))\n"
  '
}

# function vim() {
#   if [ -d "${1:-.}" ]; then
#     local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
#     yazi "$@" --cwd-file="$tmp"
#     if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
#       cd -- "$cwd"
#     fi
#     rm -f -- "$tmp"
#   else
#     nvim "$1"
#   fi
# }

# PATH
export PATH="$HOME/bin:$PATH"
export PATH=$PATH:$(go env GOPATH 2>/dev/null)/bin
export PATH="$PATH:/Users/yura/.local/bin"
export PATH="$PATH:$HOME/.config/agent-tracker/bin"

# Man page colors
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'
export MANPAGER="nvim +Man!"

# envman
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"
export PATH="~/homebrew/opt/trash-cli/bin:$PATH"
export PATH="/Applications/calibre.app/Contents/MacOS:$PATH"

source <(fzf --zsh)
export PATH="$PATH:/Applications/Surge.app/Contents/Applications"

# kimi-code
export PATH="/Users/yura/.kimi-code/bin:$PATH"

# opencode
export PATH=/Users/yura/.opencode/bin:$PATH
export PATH="$HOME/.local/bin:$PATH"

# ── tmux-sessionizer（ThePrimeagen 工作流）──────────────────
# Ctrl-a f：tmux 外也用和 tmux 里一样的 prefix+f 选项目（tmux 里 Ctrl-a 被 tmux 接管）
bindkey -s '^af' 'tmux-sessionizer\n'
# pg <名字>：在 ~/playground 开一个带日期的实验目录并直接进去
pg() {
  local name=${1:?用法: pg <名字>}
  local dir="$HOME/playground/$(date +%m%d)-$name"
  mkdir -p "$dir" || return
  [[ -d "$dir/.git" ]] || git -C "$dir" init -q
  tmux-sessionizer "$dir"
}
