# eirikr-bash-config

Comprehensive Bash configuration with modern CLI tool support and development shortcuts.

## Features

### Shell Options
- 100,000 command history with deduplication
- Case-insensitive globbing
- Directory spelling correction
- Extended pattern matching

### Modern CLI Tools
- **eza**: Modern `ls` replacement with icons and colors
- **bat**: Syntax-highlighted `cat` replacement
- **fd**: Fast `find` alternative
- **ripgrep**: Blazing fast grep
- **zoxide**: Smarter `cd` with frecency algorithm

### Development Shortcuts
- **Git**: 25+ aliases (gs, ga, gc, gp, gd, gl, etc.)
- **Docker**: Quick container management (d, dc, dps, dclean)
- **Python**: py, venv, activate shortcuts
- **Node**: npm shortcuts (npmi, npms, npmt, npmb)
- **Make/Ninja**: Parallel compilation by default

### System Utilities
- Package management (pacman, yay shortcuts)
- Network utilities (myip, localip, ports)
- System info (meminfo, cpuinfo, diskinfo)
- Archive extraction (universal `ex` function)

### CUDA Support
Optional CUDA environment for NVIDIA RTX 4070 (Compute Capability 8.9)

## Installation

### 1. Install the package

```bash
cd ~/Github/PKGBUILDS/pkgbuilds-in-progress/eirikr-bash-config
makepkg -si
```

### 2. Configure your ~/.bashrc

Add these lines to your `~/.bashrc`:

```bash
# ============================================================================
# EIRIKR BASH CONFIGURATION - MODULAR LOADING
# ============================================================================

# Load shell options and history configuration
[[ -f /usr/share/eirikr-bash-config/bashrc-shell-options.sh ]] && \
    source /usr/share/eirikr-bash-config/bashrc-shell-options.sh

# Load custom prompt
[[ -f /usr/share/eirikr-bash-config/bashrc-prompt.sh ]] && \
    source /usr/share/eirikr-bash-config/bashrc-prompt.sh

# Load environment variables
[[ -f /usr/share/eirikr-bash-config/bashrc-environment.sh ]] && \
    source /usr/share/eirikr-bash-config/bashrc-environment.sh

# Load aliases
[[ -f /usr/share/eirikr-bash-config/bashrc-aliases.sh ]] && \
    source /usr/share/eirikr-bash-config/bashrc-aliases.sh

# Load utility functions
[[ -f /usr/share/eirikr-bash-config/bashrc-functions.sh ]] && \
    source /usr/share/eirikr-bash-config/bashrc-functions.sh

# Load CUDA environment (optional - comment out if not using NVIDIA GPU)
[[ -f /usr/share/eirikr-bash-config/bashrc-cuda.sh ]] && \
    source /usr/share/eirikr-bash-config/bashrc-cuda.sh

# Load integrations (bash-completion, zoxide, nvm)
[[ -f /usr/share/eirikr-bash-config/bashrc-integrations.sh ]] && \
    source /usr/share/eirikr-bash-config/bashrc-integrations.sh

# ============================================================================
# LOCAL OVERRIDES
# ============================================================================

# Override SUDO_ASKPASS if using eirikr-askpass-unified
export SUDO_ASKPASS="/usr/bin/eirikr-askpass"

# Add your custom aliases and functions below
# ...
```

### 3. Restart your shell

```bash
exec bash
```

## Modular Structure

The configuration is split into modules for easy customization:

- **bashrc-shell-options.sh**: Shell behavior and history
- **bashrc-prompt.sh**: Custom prompt with git branch
- **bashrc-environment.sh**: Environment variables
- **bashrc-aliases.sh**: All command aliases
- **bashrc-functions.sh**: Utility functions
- **bashrc-cuda.sh**: CUDA environment (optional)
- **bashrc-integrations.sh**: Third-party tool integrations

## Customization

### Disable CUDA Support

Comment out the CUDA module in your `~/.bashrc`:

```bash
# [[ -f /usr/share/eirikr-bash-config/bashrc-cuda.sh ]] && \
#     source /usr/share/eirikr-bash-config/bashrc-cuda.sh
```

### Disable Specific Modules

Simply comment out any module you don't want to load.

### Add Local Customizations

Add your custom aliases and functions after sourcing the eirikr modules.
They will override any conflicting definitions.

## Dependencies

### Required
- bash
- coreutils

### Optional (for full features)
- eza (modern ls)
- bat (syntax-highlighted cat)
- fd (fast find)
- ripgrep (fast grep)
- zoxide (smart cd)
- ranger (file manager)
- neovim (modern vim)
- git
- docker
- python
- nodejs & npm
- cuda (NVIDIA GPU computing)

## Useful Aliases

### Navigation
- `..`, `...`, `....`: Quick parent directory navigation
- `-`: Go to previous directory

### File Listing
- `ll`: Detailed list with icons
- `lt`: Sort by modification time
- `lsize`: Sort by size
- `ltree`: Tree view (2 levels)

### Git (25+ aliases)
- `gs`: git status
- `ga`: git add
- `gc`: git commit
- `gp`: git push
- `gd`: git diff
- `gl`: git log (pretty graph)

### Docker
- `dps`: List containers
- `di`: List images
- `dstop`: Stop all containers
- `dclean`: Clean up everything

### Package Management
- `update`: sudo pacman -Syu
- `install`: sudo pacman -S
- `search`: pacman -Ss
- `cleanup`: Remove orphans

### Utilities
- `ex <file>`: Extract any archive
- `mkcd <dir>`: Create and cd into directory
- `backup <file>`: Create timestamped backup
- `sysinfo`: Show system summary
- `myip`: Show public IP
- `port <number>`: Show what's using a port

## Uninstallation

```bash
sudo pacman -Rsn eirikr-bash-config
```

Then remove the eirikr configuration lines from your `~/.bashrc`.

## License

MIT License - Feel free to use and modify as needed.

## Author

Created by eirikr for CachyOS Linux
