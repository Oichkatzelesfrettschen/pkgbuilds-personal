#!/usr/bin/env sh
# POSIX-compliant MCP server installation script
# Oaich-mcp-config - CachyOS MCP Setup
# Date: 2025-10-30

set -e

# Colors for output (POSIX-compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_warn() {
  printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_error() {
  printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Check dependencies
check_dependencies() {
  log_info "Checking dependencies..."

  if ! command -v node >/dev/null 2>&1; then
    log_error "Node.js not found. Install with: sudo pacman -S nodejs"
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log_error "Python 3 not found. Install with: sudo pacman -S python"
    exit 1
  fi

  if ! command -v uvx >/dev/null 2>&1; then
    log_error "uvx not found. Install with: sudo pacman -S uv"
    exit 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    log_warn "Git not found. Git MCP server will not work."
  fi

  log_info "All required dependencies found."
}

# Install core MCP servers
install_core_servers() {
  log_info "Installing core MCP servers..."

  # npm-based servers
  log_info "Installing filesystem server..."
  claude mcp add --transport stdio filesystem --scope user -- \
    npx -y @modelcontextprotocol/server-filesystem "$HOME" || true

  log_info "Installing memory server..."
  claude mcp add --transport stdio memory --scope user -- \
    npx -y @modelcontextprotocol/server-memory || true

  log_info "Installing everything server..."
  claude mcp add --transport stdio everything --scope user -- \
    npx -y @modelcontextprotocol/server-everything || true

  # Python-based servers (using uvx)
  log_info "Installing fetch server..."
  claude mcp add --transport stdio fetch --scope user -- \
    uvx mcp-server-fetch || true

  log_info "Installing time server..."
  claude mcp add --transport stdio time --scope user -- \
    uvx mcp-server-time || true

  if command -v git >/dev/null 2>&1; then
    log_info "Installing git server..."
    claude mcp add --transport stdio git --scope user -- \
      uvx mcp-server-git -r "$HOME" || true
  fi

  log_info "Core servers installed."
}

# Install POSIX/shell servers
install_posix_servers() {
  log_info "Installing POSIX/shell servers..."

  log_info "Installing desktop-commander..."
  claude mcp add --transport stdio desktop-commander --scope user -- \
    npx -y @wonderwhy-er/desktop-commander@latest || true

  log_info "Installing shell-command..."
  claude mcp add --transport stdio shell-command --scope user -- \
    npx -y shell-command-mcp || true

  log_info "POSIX/shell servers installed."
}

# Install development servers
install_dev_servers() {
  log_info "Installing development servers..."

  log_info "Installing npm-search..."
  claude mcp add --transport stdio npm-search --scope user -- \
    npx -y npm-search-mcp-server || true

  log_info "Installing sqlite..."
  claude mcp add --transport stdio sqlite --scope user -- \
    npx -y mcp-sqlite || true

  if command -v psql >/dev/null 2>&1; then
    log_info "Installing postgres..."
    claude mcp add --transport stdio postgres --scope user -- \
      npx -y @modelcontextprotocol/server-postgres postgresql://localhost || true
  else
    log_warn "PostgreSQL not installed. Skipping postgres MCP server."
  fi

  log_info "Development servers installed."
}

# Install browser automation servers
install_browser_servers() {
  log_info "Installing browser automation servers..."

  log_info "Installing puppeteer..."
  claude mcp add --transport stdio puppeteer --scope user -- \
    npx -y puppeteer-mcp-server || true

  log_info "Installing playwright..."
  claude mcp add --transport stdio playwright --scope user -- \
    npx -y playwright-mcp || true

  log_info "Browser automation servers installed."
}

# Install container servers
install_container_servers() {
  log_info "Installing container servers..."

  if command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
    log_info "Installing podman/docker MCP server..."
    claude mcp add --transport stdio containers --scope user -- \
      npx -y podman-mcp-server || true
  else
    log_warn "Neither podman nor docker found. Skipping container MCP server."
  fi

  log_info "Container servers installation complete."
}

# Main installation flow
main() {
  log_info "Starting MCP server installation..."
  log_info "Target: CachyOS (Arch Linux)"
  log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  check_dependencies
  echo ""

  install_core_servers
  echo ""

  install_posix_servers
  echo ""

  install_dev_servers
  echo ""

  install_browser_servers
  echo ""

  install_container_servers
  echo ""

  log_info "MCP server installation complete!"
  log_info "Run 'verify-mcp-setup.sh' to check server health."
}

main
