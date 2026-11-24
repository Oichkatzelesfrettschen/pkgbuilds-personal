#!/usr/bin/env zsh
# ============================================================================
# EIRIKR ZSH CONFIGURATION - COMPLETION ENHANCEMENTS
# ============================================================================
# Part of oichkatzelesfrettschen-zsh-config package
# This file contains maximal completion configurations with zstyle
# Synthesized from CachyOS best practices, ArchWiki, and maximal ricing
# ============================================================================

# ============================================================================
# COMPLETION ENHANCEMENTS - MAXIMAL RICING
# ============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# MATCHING & COMPLETION BEHAVIOR
# ──────────────────────────────────────────────────────────────────────────────

# Advanced case-insensitive and partial-word matching
# m:{a-zA-Z}={A-Za-z} - case insensitive
# r:|[._-]=* l:|=* - partial word completion (insert hyphens, dots, underscores)
# r:|?=** - substring completion
zstyle ':completion:*' matcher-list \
    'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=* r:|=*' \
    'l:|=* r:|=*'

# Menu-style completion with selection
zstyle ':completion:*' menu select

# Enable completion caching for better performance
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

# Rehash automatically when new binaries are added to PATH
zstyle ':completion:*' rehash true

# Complete . and .. special directories
zstyle ':completion:*' special-dirs true

# ──────────────────────────────────────────────────────────────────────────────
# VISUAL FORMATTING & COLORS
# ──────────────────────────────────────────────────────────────────────────────

# Colorful completion listings (respects LS_COLORS)
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# Format descriptions with colors
zstyle ':completion:*:corrections' format '%F{yellow}!- %d (errors: %e) -!%f'
zstyle ':completion:*:descriptions' format '%F{blue}-- %d --%f'
zstyle ':completion:*:messages' format ' %F{purple}-- %d --%f'
zstyle ':completion:*:warnings' format ' %F{red}-- no matches found --%f'
zstyle ':completion:*:default' list-prompt '%S%M matches%s'

# ──────────────────────────────────────────────────────────────────────────────
# GROUPING & ORGANIZATION
# ──────────────────────────────────────────────────────────────────────────────

# Group matches and describe
zstyle ':completion:*' group-name ''
zstyle ':completion:*:matches' group 'yes'
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:options' auto-description '%d'
zstyle ':completion:*' verbose yes

# Order of completion tags (what gets completed first)
zstyle ':completion:*:*:-command-:*:*' group-order aliases builtins functions commands

# Separate man page sections
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.*' insert-sections true

# ──────────────────────────────────────────────────────────────────────────────
# INTELLIGENT COMPLETERS & FUZZY MATCHING
# ──────────────────────────────────────────────────────────────────────────────

# Advanced completer list for intelligent matching
# _complete - normal completion
# _match - match completion without pattern matching
# _approximate - allow errors in completion (fuzzy)
# _expand_alias - expand aliases
# _prefix - complete from cursor position
zstyle ':completion:*' completer _extensions _complete _approximate _expand_alias

# Fuzzy matching - allow up to 2 errors (insertions, deletions, substitutions)
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 'reply=( $((($#PREFIX+$#SUFFIX)/3 )) numeric )'

# ──────────────────────────────────────────────────────────────────────────────
# PROCESS COMPLETION
# ──────────────────────────────────────────────────────────────────────────────

# Better process completion for kill/killall
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*' force-list always
zstyle ':completion:*:*:kill:*' insert-ids single

# ──────────────────────────────────────────────────────────────────────────────
# SSH/SCP/RSYNC HOSTNAMES
# ──────────────────────────────────────────────────────────────────────────────

# Hostname completion from known_hosts, ssh config, /etc/hosts
zstyle ':completion:*:(ssh|scp|rsync):*' hosts $([ -f ~/.ssh/config ] && grep "^Host" ~/.ssh/config | grep -v "[?*]" | cut -d " " -f2- | tr ' ' '\n')
zstyle ':completion:*:ssh:*' group-order hosts users
zstyle ':completion:*:scp:*' group-order files hosts users

# ──────────────────────────────────────────────────────────────────────────────
# DIRECTORY NAVIGATION
# ──────────────────────────────────────────────────────────────────────────────

# CD will never select the parent directory (cd ../<TAB>)
zstyle ':completion:*:cd:*' ignore-parents parent pwd

# Better directory completion with trailing slash
zstyle ':completion:*' squeeze-slashes true

# ──────────────────────────────────────────────────────────────────────────────
# COMMAND-SPECIFIC COMPLETIONS
# ──────────────────────────────────────────────────────────────────────────────

# Ignore completion functions (until the _ignored completer)
zstyle ':completion:*:functions' ignored-patterns '_*'

# Man pages - colorized section names
zstyle ':completion:*:*:man:*:*' menu select=long
zstyle ':completion:*:man:*' separate-sections true

# Sudo - enable completion for commands after sudo
zstyle ':completion::complete:*' gain-privileges 1

# Git - ignore generated files
zstyle ':completion:*:*:git:*' ignore-line true
zstyle ':completion:*:*:git-checkout:*' sort false
zstyle ':completion:*:*:git-add:*' ignore-line true

# Docker - enable completion
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# Pacman - complete packages from remote repos
zstyle ':completion:*:pacman:*' force-list always
zstyle ':completion:*:pacman:*' menu yes select

# ──────────────────────────────────────────────────────────────────────────────
# USER FILTERING
# ──────────────────────────────────────────────────────────────────────────────

# Don't complete uninteresting system users
zstyle ':completion:*:*:*:users' ignored-patterns \
    adm amanda apache at avahi avahi-autoipd beaglidx bin cacti canna \
    clamav daemon dbus distcache dnsmasq dovecot fax ftp games gdm \
    gkrellmd gopher hacluster haldaemon halt hsqldb ident junkbust kdm \
    ldap lp mail mailman mailnull man messagebus mldonkey mysql nagios \
    named netdump news nfsnobody nobody nscd ntp nut nx obsrun openvpn \
    operator pcap polkitd postfix postgres privoxy pulse pvm quagga radvd \
    rpc rpcuser rpm rtkit scard shutdown squid sshd statd svn sync tftp \
    usbmux uucp vcsa wwwrun xfs '_*'

# ... unless we really want to
zstyle '*' single-ignored show

# ──────────────────────────────────────────────────────────────────────────────
# PERFORMANCE OPTIMIZATIONS
# ──────────────────────────────────────────────────────────────────────────────

# Don't try parent directory completion if the typed string matches exactly
zstyle ':completion:*' accept-exact '*(N)'

# Pasting with tabs doesn't perform completion
zstyle ':completion:*' insert-tab pending

# ============================================================================
# CONFIGURATION FEATURES SUMMARY
# ============================================================================
#
# MATCHING:
# - Case-insensitive completion
# - Partial-word matching (Doc -> Documents)
# - Substring matching
# - Fuzzy error correction (up to 33% character errors)
#
# VISUAL:
# - Colorized completion listings
# - Grouped completions with descriptions
# - Formatted error/warning messages
# - Respects LS_COLORS for file listings
#
# SMART COMPLETIONS:
# - Command-specific optimizations (git, docker, ssh, sudo, pacman)
# - Process completion with full command display
# - SSH hostname completion from config/known_hosts
# - Directory navigation enhancements
# - Man page section separation
#
# PERFORMANCE:
# - Completion caching enabled
# - Automatic rehashing for new binaries
# - Skip parent directory in cd completions
# - Paste-friendly tab handling
#
# ============================================================================
