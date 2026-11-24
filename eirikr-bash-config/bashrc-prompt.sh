#!/usr/bin/env bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - PROMPT
# ============================================================================
# Part of eirikr-bash-config package
# This file contains custom bash prompt with git branch support
# ============================================================================

# Color definitions
RED='\[\033[0;31m\]'
GREEN='\[\033[0;32m\]'
YELLOW='\[\033[0;33m\]'
BLUE='\[\033[0;34m\]'
MAGENTA='\[\033[0;35m\]'
CYAN='\[\033[0;36m\]'
WHITE='\[\033[0;37m\]'
BOLD='\[\033[1m\]'
RESET='\[\033[0m\]'

# Git branch in prompt
parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

# Simple but informative prompt
PS1="${BOLD}${GREEN}\u@\h${RESET}:${BOLD}${BLUE}\w${RESET}${YELLOW}\$(parse_git_branch)${RESET}${BOLD}\$${RESET} "

# ============================================================================
# END OF PROMPT CONFIGURATION
# ============================================================================
