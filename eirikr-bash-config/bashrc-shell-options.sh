#!/usr/bin/env bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - SHELL OPTIONS
# ============================================================================
# Part of eirikr-bash-config package
# This file contains core bash shell options and history configuration
# ============================================================================

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# ============================================================================
# HISTORY CONFIGURATION
# ============================================================================

# History control
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=100000
HISTFILESIZE=200000
HISTIGNORE="&:[bf]g:c:clear:history:exit:q:pwd:* --help"

# Append to history file, don't overwrite
shopt -s histappend

# Save multi-line commands as one command
shopt -s cmdhist

# ============================================================================
# SHELL OPTIONS
# ============================================================================

# Check window size after each command
shopt -s checkwinsize

# Correct minor directory spelling errors
shopt -s cdspell

# Include dotfiles in pathname expansion
shopt -s dotglob

# Extended pattern matching
shopt -s extglob

# Case-insensitive globbing
shopt -s nocaseglob

# ============================================================================
# END OF SHELL OPTIONS
# ============================================================================
