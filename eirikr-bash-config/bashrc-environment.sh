#!/usr/bin/env bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - ENVIRONMENT VARIABLES
# ============================================================================
# Part of eirikr-bash-config package
# This file contains environment variable definitions
# ============================================================================

# Editor
export EDITOR='nano'
export VISUAL='nano'

# Sudo askpass - NOTE: Override this in your ~/.bashrc if using eirikr-askpass-unified
export SUDO_ASKPASS="$HOME/.local/bin/sudo-askpass"

# Less colors for man pages
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# ============================================================================
# END OF ENVIRONMENT VARIABLES
# ============================================================================
