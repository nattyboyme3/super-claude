FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fake browser opener: intercepts xdg-open calls from Claude Code and writes
# the URL to a shared IPC dir so the host launch script can open it in the
# real browser.  Must be installed as root before switching to appuser.
COPY browser-open.sh /usr/local/bin/xdg-open
RUN chmod +x /usr/local/bin/xdg-open

# Create non-root user
RUN useradd -m -s /bin/bash appuser

# Install Claude Code as appuser using the official native installer
USER appuser
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add native install location to PATH
ENV PATH="/home/appuser/.local/bin:$PATH"

WORKDIR /home/appuser
ENTRYPOINT ["claude"]
