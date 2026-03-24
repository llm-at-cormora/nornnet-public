# Logging utilities for nornnet scripts
# Article VI compliant: Structured JSON logging for OpenTelemetry collection

LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-/tmp/nornnet-build.log}"
LOG_COMPONENT="${LOG_COMPONENT:-nornnet}"

log_debug() { log_json "DEBUG" "$1"; }
log_info()  { log_json "INFO"  "$1"; }
log_warn()  { log_json "WARN"  "$1"; }
log_error() { log_json "ERROR" "$1"; }

# Structured JSON logging per Article VI
# Format: {"component": "...", "timestamp": "...", "level": "...", "message": "..."}
log_json() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # Output JSON to stdout/stderr and file
  local json_output
  json_output=$(printf '{"component":"%s","timestamp":"%s","level":"%s","message":"%s"}' \
    "$LOG_COMPONENT" "$timestamp" "$level" "$message")
  
  echo "$json_output" | tee -a "$LOG_FILE"
}

log_section() {
  echo ""
  echo "========================================"
  echo "  $1"
  echo "========================================"
  echo ""
}
