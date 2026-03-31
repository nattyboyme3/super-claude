FROM node:lts-bookworm-slim

RUN apt-get update && apt-get install -y \
    # Baseline
    curl \
    git \
    ca-certificates \
    python3 \
    # Archives & downloads
    wget \
    unzip \
    zip \
    xz-utils \
    bzip2 \
    # Text & data processing
    jq \
    ripgrep \
    fd-find \
    patch \
    xxd \
    bc \
    gettext-base \
    # Editors & viewers
    vim \
    less \
    tree \
    # Build tools
    build-essential \
    pkg-config \
    cmake \
    # Database
    sqlite3 \
    # Python ecosystem
    python3-pip \
    python3-venv \
    # Network & SSH
    openssh-client \
    rsync \
    netcat-openbsd \
    dnsutils \
    iputils-ping \
    # Process & system
    procps \
    lsof \
    file \
    shellcheck \
    parallel \
    entr \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (not in Debian's default repos)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# uv — fast Python package/version manager (static binary, no installer needed)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Fake browser opener: intercepts xdg-open calls from Claude Code and writes
# the URL to a shared IPC dir so the host launch script can open it in the
# real browser.  Must be installed as root before switching to appuser.
COPY browser-open.sh /usr/local/bin/xdg-open
RUN chmod +x /usr/local/bin/xdg-open

# Entrypoint wrapper: writes a CLAUDE.md with environment context, then execs claude.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create non-root user
RUN useradd -m -s /bin/bash appuser

# Install Claude Code as appuser using the official native installer
USER appuser
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add native install location to PATH
ENV PATH="/home/appuser/.local/bin:$PATH"

WORKDIR /home/appuser
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
