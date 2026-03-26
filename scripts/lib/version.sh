#!/usr/bin/env bash
# Version comparison and semver utilities for nornnet
# Provides version comparison, semver validation, and update detection functions

# =============================================================================
# Version Comparison Functions
# =============================================================================

# Check if version $1 is less than version $2 using semantic versioning
# Returns 0 (true) if $1 < $2, 1 (false) otherwise
# Equal versions return false (not less than)
version_lt() {
  local v1="$1"
  local v2="$2"
  
  # Equal versions are NOT less than
  [[ "$v1" = "$v2" ]] && return 1
  
  # Use sort -V for proper semantic version comparison
  [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ]
}

# Check if version $1 is greater than version $2
# Returns 0 (true) if $1 > $2, 1 (false) otherwise
version_gt() {
  local v1="$1"
  local v2="$2"
  
  [[ "$v1" = "$v2" ]] && return 1
  [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v2" ]
}

# Check if version $1 is greater than or equal to version $2
# Returns 0 (true) if $1 >= $2, 1 (false) otherwise
version_ge() {
  local v1="$1"
  local v2="$2"
  
  [[ "$v1" = "$v2" ]] && return 0
  version_gt "$v1" "$v2"
}

# Check if version $1 is less than or equal to version $2
# Returns 0 (true) if $1 <= $2, 1 (false) otherwise
version_le() {
  local v1="$1"
  local v2="$2"
  
  [[ "$v1" = "$v2" ]] && return 0
  version_lt "$v1" "$v2"
}

# =============================================================================
# Semver Validation Functions
# =============================================================================

# Check if version string is valid semver (X.Y.Z)
# Returns 0 (true) if valid, 1 (false) otherwise
is_valid_semver() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Strip 'v' prefix from version string if present
# Usage: clean_version "v1.0.0" -> "1.0.0"
strip_v_prefix() {
  local version="$1"
  echo "${version#v}"
}

# =============================================================================
# Version List Functions
# =============================================================================

# Get the highest/latest version from a space-separated list of versions
# Returns the highest version, or empty string if list is empty
get_latest_version() {
  local versions="$1"
  local highest=""
  
  for v in $versions; do
    if [ -z "$highest" ]; then
      highest="$v"
    elif version_lt "$highest" "$v"; then
      highest="$v"
    fi
  done
  
  echo "$highest"
}

# Get the lowest version from a space-separated list of versions
get_oldest_version() {
  local versions="$1"
  local lowest=""
  
  for v in $versions; do
    if [ -z "$lowest" ]; then
      lowest="$v"
    elif version_lt "$v" "$lowest"; then
      lowest="$v"
    fi
  done
  
  echo "$lowest"
}

# =============================================================================
# Update Detection Functions
# =============================================================================

# Check if an update is available
# Returns 0 (true) if update is available (current < latest), 1 (false) otherwise
update_available() {
  local current="$1"
  local latest="$2"
  version_lt "$current" "$latest"
}

# Check if rollback is possible (current > available)
# Returns 0 (true) if rollback is possible, 1 (false) otherwise
rollback_available() {
  local current="$1"
  local available="$2"
  version_gt "$current" "$available"
}

# =============================================================================
# Tag Parsing Functions
# =============================================================================

# Extract semver versions from a space-separated list of tags
# Filters out non-semver tags like 'latest', 'main', etc.
# Usage: extract_semver_tags "v1.0.0 latest v2.0.0 main" -> "1.0.0 2.0.0"
extract_semver_tags() {
  local tags="$1"
  local semver_tags=""
  
  for tag in $tags; do
    local clean="${tag#v}"  # Strip v prefix
    if is_valid_semver "$clean"; then
      semver_tags="$semver_tags $clean"
    fi
  done
  
  echo "${semver_tags# }"  # Trim leading space
}

# Parse semver tags from JSON tag list (like skopeo/cranes output)
# Usage: parse_json_tags '{"Tags":["v1.0.0","latest","v2.0.0"]}' -> "1.0.0 2.0.0"
parse_json_tags() {
  local json="$1"
  
  # Extract tags with optional v prefix
  echo "$json" | grep -oE '"v?[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | tr -d 'v' | tr '\n' ' ' | sed 's/ $//'
}

# =============================================================================
# Version Comparison Reporting
# =============================================================================

# Generate status message for update check
# Usage: update_status_message "1.0.0" "1.0.1"
update_status_message() {
  local current="$1"
  local latest="$2"
  
  if update_available "$current" "$latest"; then
    echo "Update available: $current -> $latest"
  else
    echo "No updates available"
  fi
}

# =============================================================================
# Export Functions
# =============================================================================

# Export functions for use in subshells
export -f version_lt
export -f version_gt
export -f version_ge
export -f version_le
export -f is_valid_semver
export -f strip_v_prefix
export -f get_latest_version
export -f get_oldest_version
export -f update_available
export -f rollback_available
export -f extract_semver_tags
export -f parse_json_tags
export -f update_status_message
