#!/bin/bash

# Build Claude Code Container from scratch
# Forces fresh pull of base images and rebuilds without cache

echo "Building Claude Code Container from scratch (no cache)..."
echo "This will pull the latest base images and rebuild everything."
echo ""

# Build with no cache and fresh image pulls
docker build --pull --no-cache -t claude_code_container .

if [ $? -eq 0 ]; then
    echo ""
    echo "Build completed successfully!"
    echo "Container image: claude_code_container"
else
    echo ""
    echo "Build failed. Please check the error messages above."
    exit 1
fi