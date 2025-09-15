# Claude Code CLI Container
# Purpose: Run Claude Code CLI fully autonomously in a sandboxed Docker environment
# with internet access and write access limited to the mounted project.
# Git usage is blocked via multiple layers for security.

FROM python:3.12-slim

# Core/optional build tools for compiling native extensions
# By default, include both core toolchain and extra tools for maximum compatibility
ARG INCLUDE_BUILD_TOOLS=1
ARG INCLUDE_EXTRA_TOOLS=1

# ---- 1. Base packages and tini ---------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        procps \
        lsof \
        bash \
        tini \
        wget \
        unzip; \
    rm -rf /var/lib/apt/lists/*

# ---- 2. Deny installing git via apt (defense-in-depth) ---------------------
RUN set -eux; \
    mkdir -p /etc/apt/preferences.d; \
    printf 'Package: git*\nPin: release *\nPin-Priority: -1\n' > /etc/apt/preferences.d/deny-git

# ---- 3. Install Node.js LTS (22.x) from NodeSource -------------------------
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/*

# ---- 4. Core toolchain for native builds (keeps Git blocked) ---------------
# Includes GCC toolchain, binutils, pkg-config, CMake, Ninja, and Python headers
RUN set -eux; \
    if [ "$INCLUDE_BUILD_TOOLS" = "1" ]; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            build-essential \
            binutils \
            pkg-config \
            cmake \
            ninja-build \
            python3-dev \
            libssl-dev \
            zlib1g-dev; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# ---- 5. Optional extras for performance/debugging/packaging ----------------
RUN set -eux; \
    if [ "$INCLUDE_EXTRA_TOOLS" = "1" ]; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            clang \
            lld \
            ccache \
            gdb \
            valgrind \
            patchelf; \
        rm -rf /var/lib/apt/lists/*; \
    fi

# ---- 6. Graphics/ML libraries and developer tools --------------------------
# OpenCV runtime libs, matplotlib backends, video processing, and search tools
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libgl1 \
        libglib2.0-0 \
        libfreetype6-dev \
        libpng-dev \
        libgomp1 \
        libstdc++6 \
        ffmpeg \
        ripgrep \
        sccache; \
    rm -rf /var/lib/apt/lists/*

# ---- 7. Install Claude Code from npm ---------------------------------------
RUN npm install -g @anthropic-ai/claude-code && \
    npm cache clean --force

# ---- 8. Install uv CLI (official method to /usr/local/bin) -----------------
RUN set -eux; \
    curl -LsSf https://astral.sh/uv/install.sh | sh; \
    mv /root/.local/bin/uv /usr/local/bin/uv; \
    chmod 755 /usr/local/bin/uv

# ---- 9. Create non-root user -----------------------------------------------
RUN addgroup --gid 1000 dev && \
    adduser --uid 1000 --gid 1000 --home /home/dev --shell /bin/bash dev

# ---- 10. Block git/gh/git-lfs via wrapper scripts (extra defense) ----------
RUN set -eux; \
    echo '#!/bin/sh\necho "git is disabled in this container for security" >&2; exit 127' > /usr/local/bin/git && chmod +x /usr/local/bin/git; \
    echo '#!/bin/sh\necho "git-lfs is disabled in this container for security" >&2; exit 127' > /usr/local/bin/git-lfs && chmod +x /usr/local/bin/git-lfs; \
    echo '#!/bin/sh\necho "GitHub CLI (gh) is disabled in this container for security" >&2; exit 127' > /usr/local/bin/gh && chmod +x /usr/local/bin/gh

# ---- 11. Create afplay wrapper script for notifications --------------------
RUN echo '#!/bin/bash\nprintf "\a🔔 Claude needs attention!\n"' > /usr/local/bin/afplay && \
    chmod +x /usr/local/bin/afplay

# ---- 12. Switch to non-root user -------------------------------------------
USER dev

# ---- 13. Install Rust toolchain for non-root user --------------------------
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    /home/dev/.cargo/bin/rustup toolchain install stable
ENV PATH="/home/dev/.cargo/bin:${PATH}"

# ---- 14. Environment configuration -----------------------------------------
# Claude-specific settings
ENV CLAUDE_HOME=/home/dev/.claude \
    CLAUDE_CONFIG_DIR=/home/dev/.claude \
    IS_SANDBOX=1 \
    CLAUDE_CODE_BYPASS_ALL_PERMISSIONS=1 \
    CLAUDE_CODE_SUPPRESS_UI_PROMPTS=1 \
    ANTHROPIC_DISABLE_SAFETY_CHECKS=1 \
    CLAUDE_CODE_ENTERPRISE_MODE=1 \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_ENABLE_TELEMETRY=0 \
    CLAUDE_WORKING_DIRECTORIES=/workspace:/workspace/..:/:/home:/etc:/usr:/var:/tmp:/root

# Node.js settings
ENV NODE_OPTIONS="--unhandled-rejections=strict"

# Package manager isolation - all caches are temporary
ENV UV_PROJECT_ENVIRONMENT="/tmp/container-venv" \
    UV_CACHE_DIR="/tmp/uv-cache" \
    UV_LINK_MODE="copy" \
    UV_PYTHON_PREFERENCE="managed" \
    PIP_CACHE_DIR="/tmp/pip-cache" \
    NPM_CONFIG_CACHE="/tmp/npm-cache" \
    CARGO_TARGET_DIR="/tmp/rust-target" \
    PYTHONPYCACHEPREFIX="/tmp/pycache"

# ---- 15. Project files & dependencies --------------------------------------
WORKDIR /workspace
COPY --chown=dev:dev . .

# Install Python dependencies if pyproject.toml exists
RUN if [ -f "pyproject.toml" ]; then uv sync; fi

# ---- 16. Health check -------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=3s CMD pgrep -f "claude" || exit 1

# ---- 17. Init & default cmd ------------------------------------------------
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]