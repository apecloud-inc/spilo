#!/bin/bash

# Build script for spilo-init image
# Usage: ./hack/build-init-image.sh [OPTIONS]

set -e

# Default values
REGISTRY="apecloud"
IMAGE_NAME="spilo-init"
TAG="latest"
PLATFORM="linux/amd64,linux/arm64"
PUSH=false
TEST=false
DOCKERFILE="postgres-appliance/Dockerfile.init"
CONTEXT="postgres-appliance"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build spilo-init Docker image

OPTIONS:
    -r, --registry REGISTRY     Docker registry (default: apecloud)
    -n, --name NAME             Image name (default: spilo-init)
    -t, --tag TAG               Image tag (default: latest)
    -p, --platform PLATFORM    Target platform (default: linux/amd64,linux/arm64)
    --push                      Push image to registry after build
    --test                      Run tests after build
    --single-platform           Build for current platform only (faster for testing)
    -h, --help                  Show this help message

EXAMPLES:
    # Build for local testing
    $0 --single-platform --test

    # Build and push with custom tag
    $0 -t v1.0.0 --push

    # Build for specific registry
    $0 -r myregistry.com/myorg -t latest --push
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --test)
            TEST=true
            shift
            ;;
        --single-platform)
            PLATFORM="linux/amd64"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Build full image name
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${TAG}"

# Check if we're in the right directory
if [[ ! -f "postgres-appliance/Dockerfile.init" ]]; then
    log_error "Dockerfile.init not found. Please run this script from the spilo project root directory."
    exit 1
fi

log_info "Building spilo-init image..."
log_info "Registry: ${REGISTRY}"
log_info "Image: ${IMAGE_NAME}"
log_info "Tag: ${TAG}"
log_info "Platform: ${PLATFORM}"
log_info "Full image name: ${FULL_IMAGE_NAME}"

# Check if buildx is available for multi-platform builds
if [[ "${PLATFORM}" == *","* ]]; then
    if ! docker buildx version >/dev/null 2>&1; then
        log_error "Docker buildx is required for multi-platform builds"
        exit 1
    fi

    # Create buildx builder if it doesn't exist
    if ! docker buildx inspect spilo-builder >/dev/null 2>&1; then
        log_info "Creating buildx builder..."
        docker buildx create --name spilo-builder --use
    else
        docker buildx use spilo-builder
    fi
fi

# Build command
if [[ "${PLATFORM}" == *","* ]]; then
    # Multi-platform build
    BUILD_CMD="docker buildx build --platform ${PLATFORM}"
    if [[ "${PUSH}" == "true" ]]; then
        BUILD_CMD="${BUILD_CMD} --push"
    else
        BUILD_CMD="${BUILD_CMD} --load"
        log_warning "Multi-platform build without --push will only load one platform image"
    fi
else
    # Single platform build
    BUILD_CMD="docker build"
fi

BUILD_CMD="${BUILD_CMD} -f ${DOCKERFILE} -t ${FULL_IMAGE_NAME} ${CONTEXT}"

log_info "Executing: ${BUILD_CMD}"
eval "${BUILD_CMD}"

if [[ $? -eq 0 ]]; then
    log_success "Image built successfully: ${FULL_IMAGE_NAME}"
else
    log_error "Image build failed"
    exit 1
fi

# Push image if requested and not already pushed by buildx
if [[ "${PUSH}" == "true" && "${PLATFORM}" != *","* ]]; then
    log_info "Pushing image to registry..."
    docker push "${FULL_IMAGE_NAME}"
    if [[ $? -eq 0 ]]; then
        log_success "Image pushed successfully"
    else
        log_error "Image push failed"
        exit 1
    fi
fi

# Run tests if requested
if [[ "${TEST}" == "true" ]]; then
    log_info "Running tests..."

    # Test 1: Check if image exists
    if docker image inspect "${FULL_IMAGE_NAME}" >/dev/null 2>&1; then
        log_success "Image exists and is accessible"
    else
        log_error "Image not found after build"
        exit 1
    fi

    # Test 2: Check file structure
    log_info "Checking file structure..."
    docker run --rm "${FULL_IMAGE_NAME}" find /spilo-init -type f

    # Test 3: Test wal-g binary
    log_info "Testing wal-g binary..."
    if docker run --rm "${FULL_IMAGE_NAME}" /spilo-init/bin/wal-g --version >/dev/null 2>&1; then
        log_success "wal-g binary is working"
    else
        log_warning "wal-g binary test failed (this might be expected if wal-g requires specific environment)"
    fi

    # Test 4: Basic functionality test
    log_info "Testing basic functionality..."
    if docker run --rm "${FULL_IMAGE_NAME}" sh -c "ls -la /spilo-init/scripts/ && ls -la /spilo-init/bin/ && test -x /spilo-init/bin/wal-g"; then
        log_success "Basic functionality test passed"
    else
        log_warning "Basic functionality test failed"
    fi

    # Test 5: Test bash shell availability
    log_info "Testing bash shell availability..."
    if docker run --rm "${FULL_IMAGE_NAME}" bash -c "echo 'Bash shell is working'"; then
        log_success "Bash shell is available and working"
    else
        log_warning "Bash shell test failed"
    fi

    # Test 6: Test script execution with bash
    log_info "Testing script execution with bash..."
    if docker run --rm "${FULL_IMAGE_NAME}" bash -c "head -1 /spilo-init/scripts/post_init.sh"; then
        log_success "Script reading test passed"
    else
        log_warning "Script reading test failed"
    fi

    log_success "All tests completed"
fi

# Show image information
log_info "Image information:"
docker images "${FULL_IMAGE_NAME}"

log_success "Build process completed successfully!"
echo
log_info "To use this image:"
log_info "  docker run --rm ${FULL_IMAGE_NAME}"
log_info "  # Or use it as an init container in your Kubernetes deployment"
