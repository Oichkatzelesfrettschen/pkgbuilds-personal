# Oaich-mcp-config

**Model Context Protocol (MCP) Server Configuration for CachyOS**

Version: 1.0.0
Date: 2025-10-30
Platform: CachyOS (Arch Linux) x86-64-v3
Author: Oaich

---

## Overview

This package provides a comprehensive, POSIX-compliant configuration for Model Context Protocol (MCP) servers on CachyOS. It installs and configures 15 high-value MCP servers optimized for development, system administration, and AI-assisted workflows.

### What is MCP?

Model Context Protocol (MCP) is an open standard for connecting AI applications to external systems, tools, and data sources. It enables Claude Code and other AI assistants to interact with:
- File systems and databases
- Version control (Git)
- Web content and APIs
- Container runtimes
- Browser automation
- And much more

---

## Features

### POSIX-Native Implementation
- All scripts are POSIX sh-compliant
- Validated with `yash -o posix`
- Linted with `shellcheck -s sh`
- Formatted with `shfmt -ln posix -i 2`
- No bashisms or shell-specific features

### CachyOS Optimization
- Leverages x86-64-v3 optimized packages from CachyOS repos
- Native integration with CachyOS kernel variants (BORE, EEVDF)
- Minimal overhead, maximum performance
- Follows Arch packaging standards

### Comprehensive Server Collection
**15 MCP servers across 6 categories:**
- Core functionality (5): filesystem, memory, everything, fetch, time
- POSIX/Shell (2): desktop-commander, shell-command
- Development (3): npm-search, sqlite, postgres
- Version control (1): git
- Browser automation (2): puppeteer, playwright
- Container operations (1): podman/docker
- Web search (1): brave-search

---

## Installation

### Via Pacman (Recommended)

```bash
# Build and install the package
cd /path/to/Oaich-mcp-config
makepkg -si

# Verify installation
pacman -Q Oaich-mcp-config
```

### Manual Installation

```bash
# Install dependencies
sudo pacman -S nodejs python uv git sqlite

# Run installation script
/usr/share/Oaich-mcp-config/install-mcp-servers.sh

# Verify setup
/usr/share/Oaich-mcp-config/verify-mcp-setup.sh
```

---

## Dependencies

### Required
- **nodejs** (npm + npx) - JavaScript MCP servers
- **python >=3.10** - Python MCP servers
- **uv** - Modern Python package manager (provides `uvx`)
- **git** - Required for git MCP server
- **sqlite** - Required for sqlite MCP server

### Optional
- **postgresql** - PostgreSQL MCP server support
- **podman** or **docker** - Container operations
- **chromium** - Browser automation

### POSIX Compliance Tools (Development)
- **yash** - POSIX validation
- **shellcheck** - Shell script linting
- **shfmt** - Shell script formatting

---

## MCP Server Catalog

### Core Servers

#### 1. **filesystem** (npm)
- **Package:** `@modelcontextprotocol/server-filesystem`
- **Purpose:** Secure file operations with access controls
- **Features:** Read, write, list, search files and directories
- **Status:** ✓ Working

#### 2. **memory** (npm)
- **Package:** `@modelcontextprotocol/server-memory`
- **Purpose:** Knowledge graph-based persistent memory
- **Features:** Entity storage, relationship tracking, semantic search
- **Status:** ✓ Working

#### 3. **everything** (npm)
- **Package:** `@modelcontextprotocol/server-everything`
- **Purpose:** Reference server for testing and development
- **Features:** Prompts, resources, tools, all MCP capabilities
- **Status:** ✓ Working

#### 4. **fetch** (Python/uvx)
- **Package:** `mcp-server-fetch`
- **Purpose:** Web content fetching and conversion
- **Features:** HTML to markdown, robots.txt compliance, proxy support
- **Status:** ✓ Working
- **Requirements:** Python >=3.10, uvx

#### 5. **time** (Python/uvx)
- **Package:** `mcp-server-time`
- **Purpose:** Time and timezone conversion
- **Features:** Current time, timezone conversion, formatting
- **Status:** ✓ Working
- **Requirements:** Python >=3.10, uvx

---

### POSIX/Shell Servers

#### 6. **desktop-commander** (npm)
- **Package:** `@wonderwhy-er/desktop-commander@latest`
- **Purpose:** Comprehensive terminal control and file operations
- **Features:**
  - Execute terminal commands with streaming output
  - File read/write with negative offset support (tail)
  - Surgical code editing and pattern search
  - Process management (list, kill)
  - Python/Node/R code execution
  - Background command execution
- **Status:** ✓ Working
- **Use Cases:** Complex workflows, data analysis, system administration

#### 7. **shell-command** (npm)
- **Package:** `shell-command-mcp`
- **Purpose:** Simple, secure shell command execution
- **Features:**
  - Whitelist/blacklist command filtering
  - Exit code reporting
  - Cross-platform support
- **Status:** ✓ Working
- **Use Cases:** Quick commands, package queries, git operations

---

### Development Servers

#### 8. **npm-search** (npm)
- **Package:** `npm-search-mcp-server`
- **Purpose:** Search and query npm packages
- **Features:** Package search, metadata retrieval, version information
- **Status:** ✓ Working

#### 9. **sqlite** (npm)
- **Package:** `mcp-sqlite`
- **Purpose:** SQLite database operations
- **Features:** Query, insert, update, delete, schema inspection
- **Status:** ✓ Working
- **Requirements:** sqlite3

#### 10. **postgres** (npm)
- **Package:** `@modelcontextprotocol/server-postgres`
- **Purpose:** PostgreSQL database operations
- **Features:** Read-only queries, schema inspection
- **Status:** ✓ Working
- **Requirements:** PostgreSQL installed and running

---

### Version Control

#### 11. **git** (Python/uvx)
- **Package:** `mcp-server-git`
- **Purpose:** Git repository operations
- **Features:**
  - Repository status, log, diff
  - Branch management
  - Commit, push, pull operations
  - File search within repos
- **Status:** ⚠ Configuration-dependent (needs valid git repo)
- **Requirements:** Python >=3.10, uvx, git

---

### Browser Automation

#### 12. **puppeteer** (npm)
- **Package:** `puppeteer-mcp-server`
- **Purpose:** Browser automation with Puppeteer
- **Features:** Page navigation, screenshots, form filling, scraping
- **Status:** ✓ Working
- **Requirements:** Chromium-based browser

#### 13. **playwright** (npm)
- **Package:** `playwright-mcp`
- **Purpose:** Browser automation with Playwright
- **Features:** Multi-browser support, screenshots, testing
- **Status:** ✓ Working
- **Requirements:** Chromium, Firefox, or WebKit

---

### Container Operations

#### 14. **containers** (npm)
- **Package:** `podman-mcp-server`
- **Purpose:** Container runtime operations
- **Features:**
  - List, start, stop, kill containers
  - Image management
  - Works with Podman or Docker
- **Status:** ⚠ Requires podman or docker
- **Requirements:** podman or docker

---

### Web Search

#### 15. **brave-search** (npm)
- **Package:** `@modelcontextprotocol/server-brave-search`
- **Purpose:** Web search with Brave Search API
- **Features:**
  - Web search, local search
  - Image, video, news search
  - AI-powered summarization
- **Status:** ⚠ Requires API key
- **Requirements:** Brave Search API key (set `BRAVE_API_KEY` env var)

---

## Usage

### Check Server Health

```bash
# List all configured servers
claude mcp list

# Check specific server
claude mcp get filesystem

# Test server connection
verify-mcp-setup.sh
```

### Add New Server

```bash
# npm-based server
claude mcp add --transport stdio <name> --scope user -- \
  npx -y <package-name> [args...]

# Python-based server
claude mcp add --transport stdio <name> --scope user -- \
  uvx <package-name> [args...]
```

### Remove Server

```bash
claude mcp remove <server-name> --scope user
```

---

## Configuration Scopes

MCP servers can be configured at three levels:

1. **Local** (default): Project-specific, private to you
2. **Project** (`.mcp.json`): Shared with team via version control
3. **User** (`~/.claude.json`): Available across all your projects

This package installs servers at the **user** scope for global availability.

---

## Performance

### Expected Status
- **12/15 servers working** out of the box
- **3 servers** require additional setup:
  - `git`: Needs valid git repository path
  - `containers`: Needs podman or docker installed
  - `brave-search`: Needs API key

### Success Rate
- **80%** immediate functionality
- **100%** with optional dependencies

### Resource Usage
- **Disk:** ~500 MB for all node_modules and Python packages
- **Memory:** Minimal (servers start on-demand)
- **CPU:** Negligible when idle, efficient during use

---

## Troubleshooting

### Server Won't Connect

**Symptom:** Server shows "Failed to connect"

**Solutions:**
1. First time? Wait for package to download via npx/uvx
2. Check dependencies: `verify-mcp-setup.sh`
3. Test server directly:
   ```bash
   npx -y <package-name> --help
   uvx <package-name> --help
   ```
4. Check logs: `~/.claude/debug/`

### Python Server Issues

**Symptom:** Python servers (fetch, time, git) fail

**Solution:**
```bash
# Verify uv is installed
which uvx
uvx --version

# If missing, install
sudo pacman -S uv

# Test Python server
uvx mcp-server-fetch --help
```

### npm Permission Errors

**Solution:**
```bash
# Fix npm permissions
npm config set prefix ~/.npm-global
export PATH=~/.npm-global/bin:$PATH
```

---

## POSIX Compliance

All scripts in this package are strictly POSIX sh-compliant:

### Validation
```bash
# Check POSIX compliance
yash -o posix -c 'sh -n install-mcp-servers.sh'
yash -o posix -c 'sh -n verify-mcp-setup.sh'

# Lint scripts
shellcheck -s sh install-mcp-servers.sh
shellcheck -s sh verify-mcp-setup.sh

# Format scripts
shfmt -ln posix -i 2 -w *.sh
```

### Standards
- Shebang: `#!/usr/bin/env sh`
- No bashisms: No arrays, no `[[`, no `{1..10}`
- POSIX functions: No `function` keyword
- POSIX conditionals: `[ ]` not `[[ ]]`
- POSIX echo: No `-e` flag (use `printf` instead)

---

## Integration with CachyOS

### Kernel Optimization
- Works with all CachyOS kernel variants (BORE, EEVDF, deckify)
- No kernel-specific dependencies
- Respects CachyOS performance tuning

### Package Management
- Follows Arch PKGBUILD standards
- Uses `backup=()` for configuration files
- Installs to standard locations:
  - Scripts: `/usr/share/Oaich-mcp-config/`
  - Docs: `/usr/share/doc/Oaich-mcp-config/`
- Removable via `pacman -R Oaich-mcp-config`

### x86-64-v3 Optimization
- Leverages CachyOS optimized packages when available
- Node.js compiled with v3 instructions (AVX2, FMA)
- Python packages benefit from optimized system libraries

---

## Architecture

### Why Two Package Managers?

**npm (Node.js):**
- Mature MCP ecosystem
- Wide server availability
- Fast startup times

**uvx (Python via uv):**
- Official Anthropic servers
- Ephemeral environments (no system pollution)
- Modern, fast Python package runner

### Design Principles

1. **POSIX-first:** All scripts work on any POSIX shell
2. **CachyOS-native:** No compromises for cross-platform compatibility
3. **Package everything:** System changes via PKGBUILD only
4. **Minimal state:** Servers installed on-demand, cached by npm/uv
5. **Security-conscious:** No sudo, no /usr/local, no blind trust

---

## Roadmap

### Completed ✓
- [x] Fix broken Python MCP servers
- [x] Add POSIX shell servers (desktop-commander, shell-command)
- [x] Create PKGBUILD for system-level management
- [x] POSIX-compliant scripts (yash validated)
- [x] Comprehensive documentation

### Future Enhancements
- [ ] Add GitHub MCP server (official Go-based server)
- [ ] Slack integration (requires OAuth)
- [ ] Linear project management
- [ ] Sentry error tracking
- [ ] Google Drive integration
- [ ] Custom MCP server templates
- [ ] CI/CD integration examples

---

## Files Included

```
/usr/share/Oaich-mcp-config/
├── install-mcp-servers.sh      # POSIX installation script
├── verify-mcp-setup.sh          # POSIX verification script
└── mcp-servers-template.json    # Configuration template

/usr/share/doc/Oaich-mcp-config/
└── README.md                    # This file
```

---

## Contributing

### Reporting Issues
Open issues at your git repository or contact the maintainer through the repository issue tracker

### Adding Servers
1. Test server installation manually
2. Add to `install-mcp-servers.sh`
3. Update `mcp-servers-template.json`
4. Increment `pkgver` in PKGBUILD
5. Run `namcap PKGBUILD`
6. Test installation on clean system

### Code Standards
- POSIX sh for all scripts
- Validate with yash
- Lint with shellcheck
- Format with shfmt (2-space indent)

---

## Resources

### Official Documentation
- MCP Specification: https://modelcontextprotocol.io
- MCP GitHub: https://github.com/modelcontextprotocol
- Claude Code MCP Docs: https://docs.claude.com/en/docs/claude-code/mcp

### CachyOS Resources
- CachyOS Wiki: https://wiki.cachyos.org
- CachyOS Packages: https://packages.cachyos.org
- Arch Wiki PKGBUILD: https://wiki.archlinux.org/title/PKGBUILD

### Python MCP Packages
- PyPI Search: https://pypi.org/search/?q=mcp-server
- uv Documentation: https://docs.astral.sh/uv/

### npm MCP Packages
- npm Search: https://www.npmjs.com/search?q=mcp
- MCP Registry: https://github.com/modelcontextprotocol/servers

---

## License

MIT License

Copyright (c) 2025 Oaich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## Changelog

### v1.0.0 (2025-10-30)
- Initial release
- 15 MCP servers configured
- POSIX-compliant installation and verification scripts
- Full CachyOS integration
- Comprehensive documentation

---

**Oaich-mcp-config** - Maximizing MCP on CachyOS
*Built for performance, designed for POSIX*
