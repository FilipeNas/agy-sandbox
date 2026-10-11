# ~/.bashrc: Executed by bash(1) for non-login interactive shells.

# ==============================================================================
# 1. Environment & Non-Interactive Bailout
# ==============================================================================

# Homebrew environment initialization.
# Non-interactive subshells load this automatically via BASH_ENV=/etc/sandbox-persistent.sh.
[ -f /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh

# If running non-interactively, do not load interactive settings, completions, or prompts.
case $- in
  *i*) ;;
    *) return ;;
esac

# Default terminal and editor configuration
export TERM="${TERM:-xterm-256color}"
export EDITOR="${HOMEBREW_PREFIX:-/home/linuxbrew/.linuxbrew}/bin/nano"
export VISUAL="$EDITOR"

# Kubecolor configuration (colorized kubectl output)
# - Preset: protanopia-dark (high-contrast dark theme accessible for color-blindness)
# - ObjFresh: highlights Kubernetes objects created or updated within the last 10 minutes
export KUBECOLOR_PRESET="protanopia-dark"
export KUBECOLOR_OBJ_FRESH="10m"

# Update window size after each command (adjusts LINES and COLUMNS for resizing)
shopt -s checkwinsize


# ==============================================================================
# 2. History Settings
# ==============================================================================

# History storage location and buffer size
HISTFILE=~/.bash_history
HISTSIZE=50000
HISTFILESIZE=50000

# History deduplication and security:
# - ignoreboth: ignores duplicate commands and commands starting with a space (e.g. passwords/tokens)
# - erasedups: removes all previous duplicate occurrences of the command from history
HISTCONTROL=ignoreboth:erasedups

# Append to history file when closing shell rather than overwriting it
shopt -s histappend


# ==============================================================================
# 3. Aliases
# ==============================================================================

# Core utilities with automatic colorization
alias ls='ls --color=auto'
alias ll='ls -lahF --color=auto'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Kubernetes shortcuts:
# - kubectl maps to kubecolor for syntax-highlighted terminal output
# - k is a shorthand for kubectl
alias kubectl='kubecolor'
alias k='kubectl'

# Terraform clean shortcut: removes .terraform cache directories and lock files
alias rr='rm -rf .terra*'


# ==============================================================================
# 4. Completions
# ==============================================================================

# Load kubectl bash completion if kubectl is present.
# We borrow kubectl completion for both 'kubecolor' and the 'k' alias.
# 'command kubectl' bypasses the alias above to run the actual kubectl binary.
if command -v kubectl >/dev/null 2>&1; then
  source <(command kubectl completion bash)
  complete -o default -F __start_kubectl kubecolor k 2>/dev/null || true
fi


# ==============================================================================
# 5. Prompt Customization (PS1)
# ==============================================================================

# Format: <host> <cwd> ❯
# - Hostname (\h): rendered in yellow (\e[33m)
# - Working directory basename (\W): rendered in muted gray (\e[38;5;245m)
# - Status arrow (❯): pink (\e[38;5;212m) on success (0), red (\e[38;5;203m) on failure
# Note: Escape sequences are enclosed in \[...\] so readline correctly calculates prompt width.
__prompt() {
  local ec=$?
  local arrow
  if [ "$ec" -eq 0 ]; then
    arrow='\[\e[38;5;212m\]❯\[\e[0m\]'
  else
    arrow='\[\e[38;5;203m\]❯\[\e[0m\]'
  fi
  PS1="\[\e[33m\]\h\[\e[0m\] \[\e[38;5;245m\]\W\[\e[0m\] ${arrow} "
}
PROMPT_COMMAND=__prompt


# ==============================================================================
# 6. Interactive Tool Integrations
# ==============================================================================

# zoxide: smarter cd command that learns your habits (invoked as 'z')
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

# fzf: command-line fuzzy finder (provides Ctrl+R history search, Ctrl+T file search)
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash)"
fi
