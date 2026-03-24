#!/usr/bin/env bash
# Build bootable container images for nornnet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib/logging.sh"

# Default values
LAYER="${LAYER:-base}"
TAG="${TAG:-latest}"
REGISTRY="${REGISTRY:-ghcr.io/os2sandbox}"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -l, --layer LAYER   Image layer to build (base|config|app) [default: base]
  -t, --tag TAG        Image tag [default: latest]
  -r, --registry URL   Registry URL [default: ghcr.io/os2sandbox]
  -h, --help           Show this help message

Examples:
  $0 --layer base --tag v0.1.0
  $0 --layer config --tag v0.1.0
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -l|--layer)
        LAYER="$2"; shift 2 ;;
      -t|--tag)
        TAG="$2"; shift 2 ;;
      -r|--registry)
        REGISTRY="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

build_image() {
  local layer="$1"
  local tag="$2"
  local registry="$3"
  
  local dockerfile="Containerfile.$layer"
  local image_name="$registry/nornnet-$layer:$tag"
  
  log_section "Building $layer layer"
  log_info "Dockerfile: $dockerfile"
  log_info "Image name: $image_name"
  
  if [ ! -f "$PROJECT_ROOT/$dockerfile" ]; then
    log_error "Dockerfile not found: $dockerfile"
    return 1
  fi
  
  log_info "Running podman build..."
  podman build \
    --file "$PROJECT_ROOT/$dockerfile" \
    --tag "$image_name" \
    "$PROJECT_ROOT"
  
  log_info "Build complete: $image_name"
  echo "$image_name"
}

main() {
  parse_args "$@"
  
  log_section "Nornnet Image Build"
  log_info "Layer: $LAYER"
  log_info "Tag: $TAG"
  log_info "Registry: $REGISTRY"
  
  build_image "$LAYER" "$TAG" "$REGISTRY"
}

main "$@"
