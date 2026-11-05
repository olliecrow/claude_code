# Official python:3.12-slim index. linux/amd64 and linux/arm64 both provide
# Python 3.12.16, the 2026-10-25 security release.
FROM python:3.12-slim@sha256:4840d514c583a4d3d8cad3940e68dee6f0f6f3635c12fcd0a3d74c21a5b93a54

# 1 builds the full image. 0 builds the minimal image.
ARG FULL_IMAGE=1
ARG DEBIAN_FRONTEND=noninteractive

# Pinned downloads. Change a version and its checksums together.
# Claude Code checksums come from the release manifest.json after its GPG
# signature is verified with the key in the Claude Code setup docs.
ARG CLAUDE_CODE_VERSION=2.1.311
ARG CLAUDE_CODE_SHA256_AMD64=86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada
ARG CLAUDE_CODE_SHA256_ARM64=2e2496c9a8065df93acb0fca2d341f59a6b8777649b2e025ab8c9bcd5eef61f3
# Node.js checksums come from the GPG-signed SHASUMS256.txt for the release.
ARG NODE_VERSION=22.23.4
ARG NODE_SHA256_AMD64=1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce
ARG NODE_SHA256_ARM64=6287aa46b6c375d816e63ae66d024fbbfd70404825aabdfdf898a970871d2f4b
# Rust checksums come from the GPG-signed channel-rust-<version>.toml.
ARG RUST_VERSION=1.99.1
ARG RUST_SHA256_AMD64=aded4e6c1d580415e7b594a3080d8e23e9cbe06f159f97e300aa6875211f71bf
ARG RUST_SHA256_ARM64=703b190f0d723ae68985797f3bb5f62f01b1723f138464c6f30f32b766eb0abf

# Official uv image, pinned by index digest (uv 0.13.6).
COPY --from=ghcr.io/astral-sh/uv:0.13.6@sha256:af22a52f5eafef3d78e551599d405c02df61919d18028f0cea8eda93bc9986d0 \
    /uv /uvx /usr/local/bin/

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        libstdc++6 \
        lsof \
        procps \
        ripgrep \
        tini \
        unzip \
        wget; \
    if [ "$FULL_IMAGE" = "1" ]; then \
        apt-get install -y --no-install-recommends \
            binutils \
            build-essential \
            clang \
            cmake \
            ffmpeg \
            gdb \
            libgl1 \
            libglib2.0-0 \
            libgomp1 \
            libssl-dev \
            lld \
            ninja-build \
            patchelf \
            pkg-config \
            python3-dev \
            sccache \
            valgrind \
            xz-utils \
            zlib1g-dev; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# Do not install Git through apt. Wrapper commands below also block the common
# Git entry points, but neither measure is a boundary against malicious code.
RUN set -eux; \
    mkdir -p /etc/apt/preferences.d; \
    printf 'Package: git*\nPin: release *\nPin-Priority: -1\n' \
        > /etc/apt/preferences.d/deny-git

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) platform=linux-x64; checksum="$CLAUDE_CODE_SHA256_AMD64" ;; \
        arm64) platform=linux-arm64; checksum="$CLAUDE_CODE_SHA256_ARM64" ;; \
        *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --proto '=https' -o /usr/local/bin/claude \
        "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/${platform}/claude"; \
    echo "${checksum}  /usr/local/bin/claude" | sha256sum -c -; \
    chmod 755 /usr/local/bin/claude

RUN set -eux; \
    if [ "$FULL_IMAGE" = "1" ]; then \
        case "$(dpkg --print-architecture)" in \
            amd64) node_arch=x64; node_checksum="$NODE_SHA256_AMD64"; \
                rust_triple=x86_64-unknown-linux-gnu; rust_checksum="$RUST_SHA256_AMD64" ;; \
            arm64) node_arch=arm64; node_checksum="$NODE_SHA256_ARM64"; \
                rust_triple=aarch64-unknown-linux-gnu; rust_checksum="$RUST_SHA256_ARM64" ;; \
            *) echo "unsupported architecture" >&2; exit 1 ;; \
        esac; \
        download_directory="$(mktemp -d)"; \
        cd "$download_directory"; \
        curl -fsSL --proto '=https' -o node.tar.xz \
            "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
        echo "${node_checksum}  node.tar.xz" | sha256sum -c -; \
        mkdir /opt/node; \
        tar -xJf node.tar.xz -C /opt/node --strip-components=1 --no-same-owner; \
        curl -fsSL --proto '=https' -o rust.tar.gz \
            "https://static.rust-lang.org/dist/rust-${RUST_VERSION}-${rust_triple}.tar.gz"; \
        echo "${rust_checksum}  rust.tar.gz" | sha256sum -c -; \
        tar -xzf rust.tar.gz --no-same-owner; \
        "./rust-${RUST_VERSION}-${rust_triple}/install.sh" \
            --prefix=/opt/rust \
            --components="rustc,cargo,rust-std-${rust_triple}" \
            --disable-ldconfig; \
        cd /; \
        rm -rf "$download_directory"; \
    fi

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

# Settings that apply to every Claude session in the container. Managed
# settings take precedence over user and project settings.
COPY --chmod=0644 managed-settings.json /etc/claude-code/managed-settings.json

# Python data tools live in a root-owned environment that only the full image
# creates. Project commands inside the container use their own environments.
COPY pyproject.toml uv.lock /opt/claude-tools-project/
RUN set -eux; \
    if [ "$FULL_IMAGE" = "1" ]; then \
        UV_PROJECT_ENVIRONMENT=/opt/claude-tools UV_PYTHON_DOWNLOADS=never UV_LINK_MODE=copy \
            uv sync --frozen --no-install-project --no-cache --project /opt/claude-tools-project; \
    fi

ENV PATH="/opt/claude-tools/bin:/opt/node/bin:/opt/rust/bin:${PATH}" \
    CLAUDE_CONFIG_DIR=/home/dev/.claude \
    DISABLE_AUTOUPDATER=1 \
    DISABLE_UPDATES=1 \
    NODE_OPTIONS="--unhandled-rejections=strict" \
    NPM_CONFIG_CACHE=/tmp/npm-cache \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    UV_CACHE_DIR=/tmp/uv-cache \
    UV_LINK_MODE=copy \
    PIP_CACHE_DIR=/tmp/pip-cache \
    CARGO_HOME=/tmp/cargo-home \
    CARGO_TARGET_DIR=/tmp/rust-target \
    PYTHONPYCACHEPREFIX=/tmp/pycache

USER dev
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
