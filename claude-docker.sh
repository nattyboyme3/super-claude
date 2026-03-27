#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/nattyboyme3/super-claude:latest"
WORKDIR="$(pwd)"
CONTAINER_HOME="/home/appuser"

# Claude Code respects CLAUDE_CONFIG_DIR for all credential and config storage
# (both ~/.claude.json and ~/.claude/.credentials.json resolve under this dir).
# Pointing it at a dedicated named volume keeps auth data completely separate
# from the container's home directory — no home-dir seeding required.
CLAUDE_DATA_MOUNT="/claude-data"
CLAUDE_DATA_VOLUME="super-claude-data"

# The native installer places the claude binary at ~/.local/bin/claude.
# We persist this directory in a volume so the binary survives between runs
# and updates don't require a full image pull.
CLAUDE_BIN_PATH="/home/appuser/.local/bin"
CLAUDE_BIN_VOLUME="super-claude-bin"

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

# Run setup as root to fix ownership on the data volume, then update
# Claude Code to latest using the official native installer (run as appuser).
# The bin volume persists the update across runs; both chown and the installer
# are no-ops if nothing has changed.
"$RUNTIME" run --rm --user root \
  --entrypoint sh \
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT" \
  "$IMAGE" -c "chown -R appuser:appuser $CLAUDE_DATA_MOUNT"

"$RUNTIME" run --rm --user appuser \
  --entrypoint sh \
  -v "$CLAUDE_BIN_VOLUME:$CLAUDE_BIN_PATH" \
  "$IMAGE" -c "curl -fsSL https://claude.ai/install.sh | bash"

ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT"
  -v "$CLAUDE_BIN_VOLUME:$CLAUDE_BIN_PATH"
  -e "CLAUDE_CONFIG_DIR=$CLAUDE_DATA_MOUNT"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ARGS+=(-e ANTHROPIC_API_KEY)
fi

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
