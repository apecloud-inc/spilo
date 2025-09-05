#!/bin/bash

# Quick build script for local development
# This script builds the spilo-init image for local testing

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Quick building spilo-init image for local testing...${NC}"

# Build for current platform only (much faster)
docker build \
    -f postgres-appliance/Dockerfile.init \
    -t apecloud/spilo-init:dev \
    postgres-appliance/

echo -e "${GREEN}✅ Build completed!${NC}"
echo -e "${BLUE}Image: apecloud/spilo-init:dev${NC}"

# Quick test
echo -e "${BLUE}🔍 Quick test - checking image contents:${NC}"
docker run --rm apecloud/spilo-init:dev find /spilo-init -type f

echo -e "${GREEN}✅ Quick build and test completed!${NC}"
echo -e "${BLUE}To run full tests: ./hack/build-init-image.sh --single-platform --test${NC}"
