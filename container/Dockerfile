# ---- 1. base ----------------------------------------------------------------
    FROM python:3.12-slim

    # ---- 2. system + build deps (Rust, Node, proc utilities) --------------------
    RUN set -eux; \
        # core build/runtime packages
        apt-get update; \
        apt-get install -y --no-install-recommends \
            build-essential \
            curl \
            pkg-config \
            libssl-dev \
            zlib1g-dev \
            ca-certificates \
            procps \
            lsof \
            tini; \
        \
        # Node.js LTS (22-x) repository + package
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -; \
        apt-get install -y --no-install-recommends nodejs; \
        \
        # *Hard* APT pin so even root cannot install any git-related binary packages
        printf 'Package: git*\nPin: release *\nPin-Priority: -1\n' \
            > /etc/apt/preferences.d/deny-git; \
        \
        # strip APT caches
        apt-get clean; \
        rm -rf /var/lib/apt/lists/*
    
    # ---- 3. Python package manager (uv) ----------------------------------------
    RUN pip install --no-cache-dir uv
    
    # ---- 4. Claude Code ---------------------------------------------------------
    RUN npm install -g @anthropic-ai/claude-code
    
    # ---- 5. non-root user -------------------------------------------------------
    RUN addgroup --gid 1000 dev && \
        adduser  --uid 1000 --gid 1000 --home /home/dev --shell /bin/bash dev
    
    # ---- 5a. Create afplay wrapper script ---------------------------------------
    RUN echo '#!/bin/bash\nprintf "\a🔔 Claude needs attention!\n"' > /usr/local/bin/afplay && \
        chmod +x /usr/local/bin/afplay
    
    USER dev
    
    # ---- 6. Rust toolchain ------------------------------------------------------
    RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ENV PATH="/home/dev/.cargo/bin:${PATH}"
    
    # ---- 7. stricter Node error handling ---------------------------------------
    ENV NODE_OPTIONS="--unhandled-rejections=strict"
    
    # ---- 8. Package manager isolation ------------------------------------------
    ENV UV_PROJECT_ENVIRONMENT="/tmp/container-venv"
    ENV UV_CACHE_DIR="/tmp/uv-cache"
    ENV UV_LINK_MODE="copy"
    ENV PIP_CACHE_DIR="/tmp/pip-cache" 
    ENV NPM_CONFIG_CACHE="/tmp/npm-cache"
    ENV CARGO_TARGET_DIR="/tmp/rust-target"
    ENV PYTHONPYCACHEPREFIX="/tmp/pycache"
    
    # ---- 9. project files & deps -----------------------------------------------
    WORKDIR /workspace
    COPY --chown=dev:dev . .
    RUN uv sync
    
    # ---- 10. health-check -------------------------------------------------------
    HEALTHCHECK --interval=30s --timeout=3s CMD pgrep -f "claude" || exit 1
    
    # ---- 11. init & default cmd -------------------------------------------------
    ENTRYPOINT ["/usr/bin/tini","--"]
    CMD ["bash"]