#!/usr/bin/env bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - FUNCTIONS
# ============================================================================
# Part of eirikr-bash-config package
# This file contains utility functions
# ============================================================================

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract any archive
ex() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"    ;;
            *.tar.gz)    tar xzf "$1"    ;;
            *.bz2)       bunzip2 "$1"    ;;
            *.rar)       unrar x "$1"    ;;
            *.gz)        gunzip "$1"     ;;
            *.tar)       tar xf "$1"     ;;
            *.tbz2)      tar xjf "$1"    ;;
            *.tgz)       tar xzf "$1"    ;;
            *.zip)       unzip "$1"      ;;
            *.Z)         uncompress "$1" ;;
            *.7z)        7z x "$1"       ;;
            *)           echo "'$1' cannot be extracted via ex()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Quick find file
ff() {
    find . -type f -iname "*$1*"
}

# Quick find directory
fdir() {
    find . -type d -iname "*$1*"
}

# Git clone and cd
gclone() {
    git clone "$1" && cd "$(basename "$1" .git)"
}

# Create backup of file
backup() {
    cp "$1" "$1.backup.$(date +%Y%m%d_%H%M%S)"
}

# Show directory size
dirsize() {
    du -sh "${1:-.}"
}

# Search in history
hist() {
    history | grep "$1"
}

# Create and cd to temp directory
cdtemp() {
    cd $(mktemp -d)
    pwd
}

# Quick web search
google() {
    xdg-open "https://www.google.com/search?q=$*"
}

# Show system summary
sysinfo() {
    echo "=== System Information ==="
    echo "Hostname: $(hostname)"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo "CPU: $(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)"
    echo "Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
    echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}')"
    echo "Shell: $SHELL"
}

# Port in use
port() {
    sudo lsof -i :"$1"
}

# ============================================================================
# END OF FUNCTIONS
# ============================================================================
