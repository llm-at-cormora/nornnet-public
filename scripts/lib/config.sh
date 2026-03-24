#!/usr/bin/env bash
# Configuration management library

# Load configuration from file
load_config() {
    local config_file="${CONFIG_FILE:-config/default.conf}"
    
    if [ -f "$config_file" ]; then
        # Shellcheck can't track dynamically determined files
        # shellcheck source=/dev/null
        source "$config_file"
    fi
}

# Get configuration value by key
# Usage: get_config "KEY" "default_value"
get_config() {
    local key="$1"
    local default="${2:-}"
    
    local value
    value="${!key}"
    
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}
