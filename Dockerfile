FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash appuser

# Install Claude Code as appuser using the official native installer
USER appuser
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add native install location to PATH
ENV PATH="/home/appuser/.local/bin:$PATH"

WORKDIR /home/appuser
ENTRYPOINT ["claude"]
