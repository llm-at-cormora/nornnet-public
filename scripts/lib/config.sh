# Configuration management for nornnet

CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/../../config}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/default.conf}"

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    log_debug "Loaded config from: $CONFIG_FILE"
  else
    log_warn "Config file not found: $CONFIG_FILE"
  fi
}

get_config() {
  local key="$1"
  local default="${2:-}"
  local value
  
  # Load config if not already loaded
  if [ -z "${DEFAULT_REGISTRY:-}" ]; then
    load_config
  fi
  
  # Get value using indirect variable reference
  value="${!key:-}"
  
  if [ -n "$value" ]; then
    echo "$value"
  else
    echo "$default"
  fi
}
