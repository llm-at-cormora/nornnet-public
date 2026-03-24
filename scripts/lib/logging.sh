# Logging utilities for nornnet scripts

LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-/tmp/nornnet-build.log}"

log_debug() { log "DEBUG" "$1"; }
log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_error() { log "ERROR" "$1"; }

log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_section() {
  echo ""
  echo "========================================"
  echo "  $1"
  echo "========================================"
  echo ""
}
