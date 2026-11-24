#!/bin/bash
#
# regulatory-domain.sh - Set wireless regulatory domain
# Location: /usr/lib/eirikr/regulatory-domain.sh
#
# Handles failure of /usr/bin/set-wireless-regdom script
# which occurs when regulatory database is missing or corrupted

set -u

readonly REGDOM="${1:-US}"
readonly IFACE="${2:-wlan0}"

log_info() {
  echo "[INFO] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

# Try to set regulatory domain using iw
set_regdom_iw() {
  if ! command -v iw &>/dev/null; then
    log_error "iw not found; install iw package"
    return 1
  fi

  log_info "Setting regulatory domain to $REGDOM using iw"

  if sudo iw reg set "$REGDOM" &>/dev/null; then
    log_info "Successfully set regulatory domain to $REGDOM"
    return 0
  else
    log_error "Failed to set regulatory domain with iw"
    return 1
  fi
}

# Try to set regulatory domain using uci (if available)
set_regdom_uci() {
  if ! command -v uci &>/dev/null; then
    return 1
  fi

  log_info "Setting regulatory domain to $REGDOM using uci"

  if uci set wireless.radio0.country="$REGDOM" &>/dev/null; then
    uci commit wireless
    log_info "Successfully set regulatory domain via uci"
    return 0
  fi

  return 1
}

# Verify regulatory domain was set
verify_regdom() {
  if ! command -v iw &>/dev/null; then
    log_info "Skipping verification (iw not available)"
    return 0
  fi

  local current
  current=$(iw reg get | grep -E "^country" | awk '{print $2}' | tr -d ':')

  if [[ -z "$current" ]]; then
    log_error "Could not determine current regulatory domain"
    return 1
  fi

  log_info "Current regulatory domain: $current"

  if [[ "$current" == "$REGDOM" ]]; then
    log_info "Regulatory domain verification successful"
    return 0
  else
    log_error "Regulatory domain mismatch: expected $REGDOM, got $current"
    return 1
  fi
}

main() {
  log_info "Configuring wireless regulatory domain"
  log_info "Target domain: $REGDOM"
  log_info "Target interface: $IFACE"

  # Try multiple methods in order of preference
  if set_regdom_iw; then
    verify_regdom && return 0
  fi

  if set_regdom_uci; then
    verify_regdom && return 0
  fi

  log_error "All regulatory domain methods failed"
  log_error "Your wireless may be restricted to limited channels"
  return 1
}

main "$@"
