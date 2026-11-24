#!/usr/bin/env zsh
# ============================================================================
# EIRIKR ZSH CONFIGURATION - FZF-TAB INTEGRATION
# ============================================================================
# Part of oichkatzelesfrettschen-zsh-config package
# This file contains fzf-tab setup with rich previews for enhanced completion
# ============================================================================

# ============================================================================
# FZF-TAB - ENHANCED COMPLETION WITH FZF
# ============================================================================

# Load fzf-tab when the optional fzf-tab-git package provides it (must be after
# compinit, before zsh-autosuggestions/syntax-highlighting). Without it, zsh keeps
# its native completion menu and this file configures nothing.
if [ -f /usr/share/zsh/plugins/fzf-tab-git/fzf-tab.plugin.zsh ]; then
    source /usr/share/zsh/plugins/fzf-tab-git/fzf-tab.plugin.zsh

    # Disable sort when completing git checkout
    zstyle ':completion:*:git-checkout:*' sort false

    # Set descriptions format to enable group support
    zstyle ':completion:*:descriptions' format '[%d]'

    # Set list-colors to enable filename colorizing
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

    # Force zsh not to show completion menu, which allows fzf-tab to capture it
    zstyle ':completion:*' menu no

    # Preview directory's content with eza when completing cd
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'

    # Preview files and directories
    zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [[ -d $realpath ]]; then eza -1 --color=always $realpath; elif [[ -f $realpath ]]; then bat --color=always --style=numbers --line-range=:500 $realpath 2>/dev/null || cat $realpath 2>/dev/null; fi'

    # Switch groups with < and >
    zstyle ':fzf-tab:*' switch-group '<' '>'

    # Custom fzf flags for fzf-tab
    zstyle ':fzf-tab:*' fzf-flags --height=80% --layout=reverse --border --info=inline

    # Preview for kill/ps commands
    zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
    zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'
    zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags --preview-window=down:3:wrap

    # Preview for systemctl
    zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'

    # Preview for git diff/log
    zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview 'git diff $word | delta'
    zstyle ':fzf-tab:complete:git-log:*' fzf-preview 'git log --color=always $word'
    zstyle ':fzf-tab:complete:git-show:*' fzf-preview 'git show --color=always $word | delta'

    # Preview for pacman packages
    zstyle ':fzf-tab:complete:pacman:*' fzf-preview 'pacman -Si $word 2>/dev/null || pacman -Qi $word 2>/dev/null'
fi

# ============================================================================
# FZF-TAB FEATURES
# ============================================================================
#
# Enhanced completion previews for:
# - cd: Shows directory contents with eza
# - Files: Syntax highlighting with bat, fallback to cat
# - Processes (kill/ps): Shows full command line
# - systemctl: Shows service status
# - git: Shows diffs with delta, colorized logs
# - pacman: Shows package information
#
# Navigation:
# - Tab: Accept selection
# - </>: Switch between completion groups
# - Ctrl-Space: Multi-select
# - Arrows/Ctrl-n/Ctrl-p: Navigate
#
# ============================================================================
