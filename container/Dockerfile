FROM python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de

ARG INCLUDE_BUILD_TOOLS=1
ARG INCLUDE_EXTRA_TOOLS=1
ARG CLAUDE_CODE_VERSION=2.1.218
ARG RUST_VERSION=1.88.0
ARG UV_VERSION=0.9.20
ARG DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        ffmpeg \
        gnupg \
        libgl1 \
        libglib2.0-0 \
        libgomp1 \
        libstdc++6 \
        lsof \
        procps \
        ripgrep \
        sccache \
        tini \
        unzip \
        wget; \
    rm -rf /var/lib/apt/lists/*

# Do not install Git through apt. Wrapper commands below also block the common
# Git entry points, but neither measure is a boundary against malicious code.
RUN set -eux; \
    mkdir -p /etc/apt/preferences.d; \
    printf 'Package: git*\nPin: release *\nPin-Priority: -1\n' \
        > /etc/apt/preferences.d/deny-git

RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    if [ "$INCLUDE_BUILD_TOOLS" = "1" ]; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            binutils \
            build-essential \
            cmake \
            libssl-dev \
            ninja-build \
            pkg-config \
            python3-dev \
            zlib1g-dev; \
        rm -rf /var/lib/apt/lists/*; \
    fi

RUN set -eux; \
    if [ "$INCLUDE_EXTRA_TOOLS" = "1" ]; then \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            ccache \
            clang \
            gdb \
            lld \
            patchelf \
            valgrind; \
        rm -rf /var/lib/apt/lists/*; \
    fi

RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force \
    && python -m pip install --disable-pip-version-check --no-cache-dir \
        --root-user-action=ignore "uv==${UV_VERSION}"

RUN addgroup --gid 1000 dev \
    && adduser --disabled-password --gecos "" --uid 1000 --gid 1000 \
        --home /home/dev --shell /bin/bash dev

RUN set -eux; \
    printf '%s\n' '#!/bin/sh' 'echo "git is disabled in this container" >&2' 'exit 127' \
        > /usr/local/bin/git; \
    printf '%s\n' '#!/bin/sh' 'echo "git-lfs is disabled in this container" >&2' 'exit 127' \
        > /usr/local/bin/git-lfs; \
    printf '%s\n' '#!/bin/sh' 'echo "gh is disabled in this container" >&2' 'exit 127' \
        > /usr/local/bin/gh; \
    printf '%s\n' '#!/bin/sh' 'printf "\\aClaude needs attention.\\n"' \
        > /usr/local/bin/afplay; \
    chmod 755 /usr/local/bin/git /usr/local/bin/git-lfs /usr/local/bin/gh /usr/local/bin/afplay

USER dev

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain "${RUST_VERSION}"

ENV PATH="/home/dev/.cargo/bin:/tmp/container-venv/bin:${PATH}" \
    CLAUDE_CONFIG_DIR=/home/dev/.claude \
    DISABLE_AUTOUPDATER=1 \
    NODE_OPTIONS="--unhandled-rejections=strict" \
    NPM_CONFIG_CACHE=/tmp/npm-cache \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    UV_PROJECT_ENVIRONMENT=/tmp/container-venv \
    UV_CACHE_DIR=/tmp/uv-cache \
    UV_LINK_MODE=copy \
    PIP_CACHE_DIR=/tmp/pip-cache \
    CARGO_TARGET_DIR=/tmp/rust-target \
    PYTHONPYCACHEPREFIX=/tmp/pycache

WORKDIR /workspace
COPY --chown=dev:dev pyproject.toml uv.lock ./
RUN uv sync --frozen

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
