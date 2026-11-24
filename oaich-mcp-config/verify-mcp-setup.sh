#!/usr/bin/env sh
# POSIX-compliant MCP server verification script
# Oaich-mcp-config - CachyOS MCP Setup
# Date: 2025-10-30

set -e

# Colors for output (POSIX-compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_header() {
  printf "\n${BLUE}=== %s ===${NC}\n" "$1"
}

# Check system requirements
check_system() {
  log_header "System Information"

  printf "OS: "
  uname -s

  printf "Kernel: "
  uname -r

  printf "Architecture: "
  uname -m

  printf "Distribution: "
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf "%s\n" "$PRETTY_NAME"
  else
    printf "Unknown\n"
  fi
}

# Check dependencies
check_dependencies() {
  log_header "Dependency Check"

  # Node.js
  if command -v node >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} Node.js: "
    node --version
  else
    printf "${RED}✗${NC} Node.js: Not installed\n"
  fi

  # npm
  if command -v npm >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} npm: "
    npm --version
  else
    printf "${RED}✗${NC} npm: Not installed\n"
  fi

  # Python
  if command -v python3 >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} Python: "
    python3 --version
  else
    printf "${RED}✗${NC} Python: Not installed\n"
  fi

  # uv/uvx
  if command -v uvx >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} uvx: "
    uvx --version
  else
    printf "${RED}✗${NC} uvx: Not installed\n"
  fi

  # Git
  if command -v git >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} Git: "
    git --version
  else
    printf "${YELLOW}⚠${NC} Git: Not installed (optional)\n"
  fi

  # SQLite
  if command -v sqlite3 >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} SQLite: "
    sqlite3 --version
  else
    printf "${YELLOW}⚠${NC} SQLite: Not installed (optional)\n"
  fi

  # PostgreSQL
  if command -v psql >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} PostgreSQL: "
    psql --version
  else
    printf "${YELLOW}⚠${NC} PostgreSQL: Not installed (optional)\n"
  fi

  # Podman/Docker
  if command -v podman >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} Podman: "
    podman --version
  elif command -v docker >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} Docker: "
    docker --version
  else
    printf "${YELLOW}⚠${NC} Containers: Neither podman nor docker installed\n"
  fi
}

# Check MCP server health
check_mcp_servers() {
  log_header "MCP Server Health Check"

  if ! command -v claude >/dev/null 2>&1; then
    log_error "claude command not found. Cannot check MCP servers."
    return 1
  fi

  log_info "Running server health check..."
  claude mcp list
}

# Count servers
count_servers() {
  log_header "Server Statistics"

  if ! command -v claude >/dev/null 2>&1; then
    log_warn "claude command not found. Cannot count servers."
    return 0
  fi

  TOTAL=$(claude mcp list 2>/dev/null | grep -c -E "(✓|✗)" || echo "0")
  WORKING=$(claude mcp list 2>/dev/null | grep -c "✓" || echo "0")
  FAILED=$((TOTAL - WORKING))

  printf "Total servers: %d\n" "$TOTAL"
  printf "${GREEN}Working: %d${NC}\n" "$WORKING"

  if [ "$FAILED" -gt 0 ]; then
    printf "${RED}Failed: %d${NC}\n" "$FAILED"
  else
    printf "Failed: 0\n"
  fi

  if [ "$TOTAL" -gt 0 ]; then
    SUCCESS_RATE=$((WORKING * 100 / TOTAL))
    printf "Success rate: %d%%\n" "$SUCCESS_RATE"
  fi
}

# Test individual server
test_server() {
  SERVER_NAME="$1"
  COMMAND="$2"

  log_info "Testing ${SERVER_NAME}..."

  if eval "$COMMAND" >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} %s\n" "$SERVER_NAME"
    return 0
  else
    printf "${RED}✗${NC} %s\n" "$SERVER_NAME"
    return 1
  fi
}

# POSIX compliance check
check_posix_compliance() {
  log_header "POSIX Compliance Check"

  # Check shell
  if command -v yash >/dev/null 2>&1; then
    log_info "yash found - can validate POSIX scripts"
    printf "${GREEN}✓${NC} POSIX validator: yash\n"
  else
    log_warn "yash not found - install for POSIX validation"
    printf "${YELLOW}⚠${NC} POSIX validator: yash not installed\n"
  fi

  # Check shellcheck
  if command -v shellcheck >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} Shell linter: shellcheck\n"
  else
    log_warn "shellcheck not found - install for shell script linting"
    printf "${YELLOW}⚠${NC} Shell linter: shellcheck not installed\n"
  fi

  # Check shfmt
  if command -v shfmt >/dev/null 2>&1; then
    printf "${GREEN}✓${NC} Shell formatter: shfmt\n"
  else
    log_warn "shfmt not found - install for shell script formatting"
    printf "${YELLOW}⚠${NC} Shell formatter: shfmt not installed\n"
  fi
}

# Performance info
check_performance() {
  log_header "Performance Information"

  # CPU info
  if [ -f /proc/cpuinfo ]; then
    printf "CPU: "
    grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs || echo "Unknown"
  fi

  # Memory info
  if [ -f /proc/meminfo ]; then
    printf "RAM: "
    grep "MemTotal" /proc/meminfo | awk '{printf "%.1f GB\n", $2/1024/1024}' || echo "Unknown"
  fi

  # Disk info for home
  printf "Home disk usage: "
  df -h "$HOME" | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}'

  # Node.js version (x86-64-v3 optimized)
  if command -v node >/dev/null 2>&1; then
    printf "Node architecture: "
    node -p "process.arch" 2>/dev/null || echo "Unknown"
  fi
}

# Main verification flow
main() {
  log_info "Starting MCP setup verification..."
  log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"

  check_system
  check_dependencies
  check_posix_compliance
  check_performance
  check_mcp_servers
  count_servers

  echo ""
  log_info "Verification complete!"
  log_info "For detailed server info, run: claude mcp list"
}

main
