#!/usr/bin/env bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - ALIASES
# ============================================================================
# Part of eirikr-bash-config package
# This file contains all command aliases
# ============================================================================

# ============================================================================
# NAVIGATION ALIASES
# ============================================================================

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# ============================================================================
# LIST FILES - USING EZA (MODERN LS REPLACEMENT)
# ============================================================================

alias ls='eza --color=always --group-directories-first --icons'
alias ll='eza -lah --color=always --group-directories-first --icons'
alias la='eza -a --color=always --group-directories-first --icons'
alias l='eza -lah --color=always --group-directories-first --icons'
alias lt='eza -lah --sort=modified --color=always --group-directories-first --icons'
alias ltree='eza --tree --level=2 --color=always --group-directories-first --icons'
alias lsize='eza -lah --sort=size --color=always --group-directories-first --icons'
alias lcount='ls -1 | wc -l'

# Traditional ls (if needed)
alias lls='/usr/bin/ls --color=auto -hv'

# ============================================================================
# GREP WITH COLOR - RIPGREP ENHANCED
# ============================================================================

alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias rg='rg --color=always --smart-case'

# ============================================================================
# MODERN CLI TOOLS
# ============================================================================

alias cat='bat --style=auto'
alias catp='bat --style=plain'
alias catcat='/usr/bin/cat'
alias find='fd'
alias findfind='/usr/bin/find'
alias r='ranger'

# ============================================================================
# UTILITIES
# ============================================================================

# Diff with color
alias diff='diff --color=auto'

# IP with color
alias ip='ip -color=auto'

# Clear screen
alias c='clear'
alias cls='clear'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Shortcuts
alias h='history'
alias j='jobs'
alias v='$EDITOR'
alias vim='nvim'
alias vi='nvim'

# ============================================================================
# ARCH/CACHYOS PACKAGE MANAGEMENT
# ============================================================================

alias pacman='pacman --color=always'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'
alias search='pacman -Ss'
alias remove='sudo pacman -Rsn'
alias rmpkg='sudo pacman -Rsn'
alias cleanch='sudo pacman -Scc'
alias fixpacman='sudo rm /var/lib/pacman/db.lck'
alias orphans='pacman -Qtdq'
alias cleanup='sudo pacman -Rsn $(pacman -Qtdq)'

alias yayupdate='yay -Syu'
alias yayinstall='yay -S'
alias yaysearch='yay -Ss'

alias pkginfo='pacman -Qi'
alias pkgfiles='pacman -Ql'
alias pkgown='pacman -Qo'

alias mirrors='sudo reflector --verbose --latest 10 --sort rate --save /etc/pacman.d/mirrorlist'
alias jctl='journalctl -p 3 -xb'
alias failed='systemctl --failed'

# ============================================================================
# DEVELOPMENT & GIT
# ============================================================================

alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gp='git push'
alias gpl='git pull'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate'
alias gla='git log --oneline --graph --decorate --all'
alias gb='git branch'
alias gba='git branch -a'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gm='git merge'
alias gr='git remote -v'
alias gf='git fetch'
alias gst='git stash'
alias gstp='git stash pop'

alias make='make -j$(nproc)'
alias ninja='ninja -j$(nproc)'
alias n='ninja'
alias cm='cmake'
alias cmb='cmake --build .'

# ============================================================================
# DOCKER
# ============================================================================

alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drm='docker rm'
alias drmi='docker rmi'
alias dstop='docker stop $(docker ps -aq)'
alias dclean='docker system prune -af'

# ============================================================================
# PYTHON
# ============================================================================

alias py='python3'
alias python='python3'
alias pip='pip3'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate'

# ============================================================================
# NODE/NPM
# ============================================================================

alias npm='npm'
alias npmi='npm install'
alias npms='npm start'
alias npmt='npm test'
alias npmd='npm run dev'
alias npmb='npm run build'

# ============================================================================
# SYSTEM UTILITIES
# ============================================================================

alias myip='curl -s https://api.ipify.org && echo'
alias localip="ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1"
alias ports='netstat -tulanp'
alias ping='ping -c 5'
alias fastping='ping -c 100 -s 1'

alias meminfo='free -h'
alias cpuinfo='lscpu'
alias diskinfo='df -h'
alias usage='du -h -d 1 | sort -h'
alias bigfiles='find . -type f -exec du -h {} + | sort -rh | head -n 20'
alias temp='sensors'

alias psa='ps aux'
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'
alias killall='killall -v'
alias htop='htop -t'

alias mktar='tar -cvf'
alias mkbz2='tar -cvjf'
alias mkgz='tar -cvzf'
alias untar='tar -xvf'

alias pbcopy='wl-copy'
alias pbpaste='wl-paste'

alias mkdir='mkdir -pv'
alias wget='wget -c'
alias path='echo -e ${PATH//:/\\n}'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias nowdate='date +"%Y-%m-%d"'

alias please='sudo'
alias fucking='sudo'
alias tb='nc termbin.com 9999'
alias weather='curl wttr.in'

# ============================================================================
# END OF ALIASES
# ============================================================================
