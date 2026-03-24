#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/gendosu/claude-code-docker:latest"
WORKDIR="$(pwd)"
CONTAINER_HOME="/home/appuser"

# Claude Code respects CLAUDE_CONFIG_DIR for all credential and config storage
# (both ~/.claude.json and ~/.claude/.credentials.json resolve under this dir).
# Pointing it at a dedicated named volume keeps auth data completely separate
# from the container's home directory — no home-dir seeding required.
CLAUDE_DATA_MOUNT="/claude-data"
CLAUDE_DATA_VOLUME="super-claude-data"

# The image ships with a pinned Claude Code version; we keep the live package
# in its own volume so updates survive between runs. The volume is mounted at
# the @anthropic-ai parent (not the package dir itself) so npm's atomic rename
# can complete without EBUSY errors.
CLAUDE_PKG_PATH="/usr/local/lib/node_modules/@anthropic-ai"
CLAUDE_PKG_VOLUME="super-claude-pkg"

# Detect available container runtime
detect_runtime() {
  if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    echo "docker"
  elif command -v container &>/dev/null; then
    echo "container"
  elif command -v nerdctl &>/dev/null; then
    echo "nerdctl"
  else
    echo ""
  fi
}

RUNTIME="$(detect_runtime)"

if [[ -z "$RUNTIME" ]]; then
  echo ""
  echo "No container runtime found. Install one of the following:"
  echo ""
  echo "  Docker Desktop (most compatible):"
  echo "    brew install --cask docker-desktop"
  echo ""
  echo "  Apple Container (Apple Silicon + macOS 15+ only):"
  echo "    brew install container"
  echo ""
  echo "  Rancher Desktop:"
  echo "    brew install --cask rancher"
  echo "    or download from https://rancherdesktop.io"
  echo ""
  exit 1
fi

# Always pull the latest image so Claude Code is up to date.
"$RUNTIME" pull "$IMAGE"

# Run as root to: (1) update Claude Code to the latest published version,
# and (2) fix ownership on the data volume so appuser can write to it.
# The package volume persists the update across runs; the chown is a no-op
# after the first launch.
"$RUNTIME" run --rm --user root \
  --entrypoint sh \
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT" \
  -v "$CLAUDE_PKG_VOLUME:$CLAUDE_PKG_PATH" \
  "$IMAGE" -c "
    npm install -g @anthropic-ai/claude-code@latest --no-fund --no-audit --quiet
    chown -R appuser:appuser $CLAUDE_DATA_MOUNT
  "

ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT"
  -v "$CLAUDE_PKG_VOLUME:$CLAUDE_PKG_PATH"
  -e "CLAUDE_CONFIG_DIR=$CLAUDE_DATA_MOUNT"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ARGS+=(-e ANTHROPIC_API_KEY)
fi

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
