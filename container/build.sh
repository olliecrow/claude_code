#!/usr/bin/env bash
set -euo pipefail

# Build Claude Code CLI container image (always fresh, no cache)
#
# Usage:
#   ./build.sh [--minimal]
#
# Options:
#   --minimal    Build minimal image without extra build tools

cd "$(dirname "$0")"

# Parse command line arguments
MINIMAL_BUILD=0
for arg in "$@"; do
    case $arg in
        --minimal)
            MINIMAL_BUILD=1
            shift
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--minimal]"
            exit 1
            ;;
    esac
done

# Set build configuration
if [ $MINIMAL_BUILD -eq 1 ]; then
    INCLUDE_BUILD_TOOLS=0
    INCLUDE_EXTRA_TOOLS=0
    echo "Building minimal claude_code_container (no build tools or extras)..."
else
    INCLUDE_BUILD_TOOLS=1
    INCLUDE_EXTRA_TOOLS=1
    echo "Building full claude_code_container with all tools..."
fi

echo "Configuration:"
echo "  - Core native build toolchain: $([ $INCLUDE_BUILD_TOOLS -eq 1 ] && echo 'YES' || echo 'NO')"
echo "  - Extra tools (clang, gdb, valgrind, etc.): $([ $INCLUDE_EXTRA_TOOLS -eq 1 ] && echo 'YES' || echo 'NO')"
echo "  - Developer tools (ripgrep, ffmpeg, sccache): YES (always included)"
echo "  - Graphics/ML libraries: YES (always included)"
echo "  - Git blocking: YES (multiple layers)"
echo ""
echo "Building Claude Code Container from scratch (no cache)..."
echo "This will pull the latest base images and rebuild everything."
echo ""

# Build with no cache and fresh image pulls
CMD=(docker build --pull --no-cache -t claude_code_container)
CMD+=(--build-arg INCLUDE_BUILD_TOOLS=$INCLUDE_BUILD_TOOLS)
CMD+=(--build-arg INCLUDE_EXTRA_TOOLS=$INCLUDE_EXTRA_TOOLS)
CMD+=(.)

"${CMD[@]}"

if [ $? -eq 0 ]; then
    echo ""
    echo "Build completed successfully!"
    echo "Container image: claude_code_container"
    echo ""
    echo "To run the container:"
    echo "  ./run.sh /path/to/project"
    echo ""
    echo "To get a shell in the container:"
    echo "  ./run.sh /path/to/project --shell"
else
    echo ""
    echo "Build failed. Please check the error messages above."
    exit 1
fi