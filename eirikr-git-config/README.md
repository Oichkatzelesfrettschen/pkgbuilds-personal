# eirikr-git-config

Optimized Git configuration with performance enhancements, LFS support, and comprehensive global gitignore.

## Features

### Performance Optimizations
- **FSMonitor**: Faster `git status` on large repositories
- **Untracked Cache**: Cache untracked files for speed
- **Many Files**: Optimize for repos with thousands of files
- **Protocol v2**: Faster network operations

### Git LFS Support
Pre-configured support for Git Large File Storage (requires git-lfs package).

### Global Gitignore
Automatically ignores common files across all repositories:
- Editor/IDE files (VSCode, IntelliJ, Vim, Emacs)
- OS files (.DS_Store, Thumbs.db, .directory)
- Build artifacts (*.o, *.so, dist/, build/, target/)
- Language-specific (\_\_pycache\_\_, node_modules/, *.class)
- Secrets (.env, *.key, *.pem, credentials.json)
- Logs (*.log, npm-debug.log*)

### Useful Aliases
- `st`: Status with short format
- `co`: Checkout
- `br`: Branch
- `visual`: Pretty log graph
- `amend`: Amend last commit
- `undo`: Undo last commit (keep changes)
- `wip`: Quick work-in-progress commit

### Smart Defaults
- Default branch: `main`
- Editor: `nano`
- Auto-prune on fetch
- Abbreviated commits in logs
- Color UI enabled

## Installation

### 1. Install the package

```bash
cd eirikr-git-config
makepkg -si
```

### 2. Run the setup script

```bash
eirikr-git-setup
```

The script will:
1. Backup your existing `.gitconfig` (if exists)
2. Prompt for your name and email
3. Create optimized git configuration
4. Set up global gitignore
5. Show configuration summary

### 3. Verify installation

```bash
git config --global --list
```

## Manual Configuration

If you prefer manual setup:

1. Copy template to your home directory:
```bash
cp /usr/share/eirikr-git-config/gitconfig.template ~/.gitconfig
```

2. Edit with your information:
```bash
nano ~/.gitconfig
# Replace __GIT_NAME__ with your name
# Replace __GIT_EMAIL__ with your email
```

3. Global gitignore is automatically configured to:
```
/usr/share/eirikr-git-config/gitignore_global
```

## Configuration Details

### Performance Features

**FSMonitor**
```ini
[core]
    fsmonitor = true
```
Uses filesystem monitoring for faster status checks.

**Untracked Cache**
```ini
[core]
    untrackedCache = true
```
Caches untracked files to avoid repeated scans.

**Many Files**
```ini
[feature]
    manyFiles = true
```
Optimizes for repositories with many files.

**Protocol v2**
```ini
[protocol]
    version = 2
```
Uses Git protocol v2 for faster network operations.

### Git LFS Configuration

```ini
[filter "lfs"]
    process = git-lfs filter-process
    required = true
    clean = git-lfs clean -- %f
    smudge = git-lfs smudge -- %f
```

Install Git LFS support:
```bash
sudo pacman -S git-lfs
git lfs install
```

### Fetch Settings

```ini
[fetch]
    prune = true
    pruneTags = true
```

Automatically cleans up deleted remote branches and tags.

## Global Gitignore Categories

### Editor Files
- `.vscode/`, `.idea/` (IDEs)
- `*.swp`, `*~` (Vim, Emacs)
- `*.sublime-*` (Sublime Text)

### OS Files
- `.DS_Store` (macOS)
- `Thumbs.db`, `Desktop.ini` (Windows)
- `.directory` (Linux)

### Build Artifacts
- `*.o`, `*.so`, `*.dll` (Compiled files)
- `dist/`, `build/`, `target/` (Build directories)
- `*.exe`, `*.out` (Executables)

### Language-Specific
- `__pycache__/`, `*.pyc` (Python)
- `node_modules/`, `*.log` (Node.js)
- `*.class`, `*.jar` (Java)
- `target/`, `Cargo.lock` (Rust)

### Secrets
- `.env`, `.env.local` (Environment files)
- `*.key`, `*.pem`, `*.crt` (Keys/certificates)
- `secrets.yml`, `credentials.json` (Secrets)

## Useful Aliases

After installation, you can use these shortcuts:

```bash
git st              # Short status
git co main         # Checkout main
git br              # List branches
git visual          # Pretty log graph
git amend           # Amend last commit
git undo            # Undo last commit (keep changes)
git wip             # Quick WIP commit
git stash-all       # Stash including untracked files
```

## Testing Configuration

### Test performance features:
```bash
# Check fsmonitor status
git config --global core.fsmonitor

# Check untracked cache
git config --global core.untrackedCache

# Test on a large repo
cd /path/to/large/repo
time git status
```

### Test global gitignore:
```bash
# Create a test repo
mkdir test-repo && cd test-repo
git init

# Create ignored files
touch .DS_Store node_modules/ .env

# Check status (should be clean)
git status
```

## Customization

### Edit Configuration
```bash
nano ~/.gitconfig
```

### Add Custom Aliases
```bash
git config --global alias.myalias "log --oneline"
```

### Modify Global Gitignore
```bash
# Edit system-wide ignore patterns
sudo nano /usr/share/eirikr-git-config/gitignore_global

# Or create local additions
nano ~/.gitignore_global_local
git config --global core.excludesfile ~/.gitignore_global_local
```

## Uninstallation

```bash
# Remove package
sudo pacman -Rsn eirikr-git-config

# Restore previous config (if backup exists)
mv ~/.gitconfig.backup-YYYYMMDD_HHMMSS ~/.gitconfig
```

## Dependencies

### Required
- git

### Optional
- **git-lfs**: Large file storage support
  ```bash
  sudo pacman -S git-lfs
  ```

- **git-delta**: Enhanced diff viewer
  ```bash
  sudo pacman -S git-delta
  ```

## Compatibility

Works with:
- ✅ GitHub
- ✅ GitLab
- ✅ Bitbucket
- ✅ Gitea
- ✅ Any Git server

## License

MIT License - Feel free to use and modify as needed.

## Author

Created by eirikr for CachyOS Linux

## See Also

- [Git Documentation](https://git-scm.com/doc)
- [Git LFS](https://git-lfs.github.com/)
- [Git Protocol v2](https://git-scm.com/docs/protocol-v2)
