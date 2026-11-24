#!/usr/bin/env bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - INTEGRATIONS
# ============================================================================
# Part of eirikr-bash-config package
# This file contains third-party tool integrations
# ============================================================================

# ============================================================================
# BASH COMPLETION
# ============================================================================

# Enable bash completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# ============================================================================
# MODERN TOOL INTEGRATIONS
# ============================================================================

# Zoxide - smarter cd command
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init bash)"
fi

# NVM - Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ============================================================================
# END OF INTEGRATIONS
# ============================================================================
