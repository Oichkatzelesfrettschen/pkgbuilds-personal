#!/bin/bash
# ============================================================================
# EIRIKR GIT CONFIGURATION - INTERACTIVE SETUP SCRIPT
# ============================================================================
# This script configures git with optimized settings and global gitignore
# ============================================================================

set -e

echo "============================================================================"
echo "EIRIKR GIT CONFIGURATION SETUP"
echo "============================================================================"
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "ERROR: git is not installed"
    echo "Install it with: sudo pacman -S git"
    exit 1
fi

# Backup existing config
if [ -f ~/.gitconfig ]; then
    BACKUP_FILE=~/.gitconfig.backup-$(date +%Y%m%d_%H%M%S)
    cp ~/.gitconfig "$BACKUP_FILE"
    echo "✅ Existing .gitconfig backed up to: $BACKUP_FILE"
    echo ""
fi

# Get current git user info (if exists)
CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

# Prompt for user information
echo "Git User Configuration"
echo "----------------------"
echo ""

if [ -n "$CURRENT_NAME" ]; then
    read -p "Enter your name [$CURRENT_NAME]: " GIT_NAME
    GIT_NAME=${GIT_NAME:-$CURRENT_NAME}
else
    read -p "Enter your name: " GIT_NAME
fi

if [ -n "$CURRENT_EMAIL" ]; then
    read -p "Enter your email [$CURRENT_EMAIL]: " GIT_EMAIL
    GIT_EMAIL=${GIT_EMAIL:-$CURRENT_EMAIL}
else
    read -p "Enter your email: " GIT_EMAIL
fi

echo ""

# Validate input
if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    echo "ERROR: Name and email are required"
    exit 1
fi

# Create config from template
echo "Creating git configuration..."
cp /usr/share/eirikr-git-config/gitconfig.template ~/.gitconfig
sed -i "s/__GIT_NAME__/$GIT_NAME/g" ~/.gitconfig
sed -i "s/__GIT_EMAIL__/$GIT_EMAIL/g" ~/.gitconfig

echo "✅ Git configuration created"
echo ""

# Verify configuration
echo "Configuration Summary:"
echo "----------------------"
echo "Name:  $(git config --global user.name)"
echo "Email: $(git config --global user.email)"
echo "Default Branch: $(git config --global init.defaultBranch)"
echo "Editor: $(git config --global core.editor)"
echo "Global Gitignore: $(git config --global core.excludesfile)"
echo "FSMonitor: $(git config --global core.fsmonitor)"
echo "Untracked Cache: $(git config --global core.untrackedCache)"
echo "Protocol Version: $(git config --global protocol.version)"
echo ""

# Check for optional dependencies
echo "Optional Features:"
echo "------------------"

if command -v git-lfs &> /dev/null; then
    echo "✅ Git LFS installed (large file support enabled)"
else
    echo "⚠️  Git LFS not installed (install with: sudo pacman -S git-lfs)"
fi

if command -v delta &> /dev/null; then
    echo "✅ Delta installed (enhanced diffs available)"
else
    echo "ℹ️  Delta not installed (optional, install with: sudo pacman -S git-delta)"
fi

echo ""
echo "============================================================================"
echo "✅ EIRIKR GIT CONFIGURATION COMPLETE"
echo "============================================================================"
echo ""
echo "Your git is now configured with:"
echo "  • Performance optimizations (fsmonitor, untrackedCache, manyFiles)"
echo "  • Global gitignore for IDE and build artifacts"
echo "  • Git LFS support (if installed)"
echo "  • Protocol v2 for faster operations"
echo "  • Useful aliases (st, co, br, visual, amend, undo)"
echo ""
echo "To view your configuration:"
echo "  git config --global --list"
echo ""
echo "To edit your configuration:"
echo "  nano ~/.gitconfig"
echo ""
