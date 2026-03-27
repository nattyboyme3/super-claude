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

# Pull only if a newer image exists; --quiet suppresses the digest noise.
CURRENT_ID="$("$RUNTIME" inspect --format='{{.Id}}' "$IMAGE" 2>/dev/null || true)"
"$RUNTIME" pull --quiet "$IMAGE"
NEW_ID="$("$RUNTIME" inspect --format='{{.Id}}' "$IMAGE")"
if [[ "$CURRENT_ID" != "$NEW_ID" ]]; then
  NEW_VERSION="$("$RUNTIME" run --rm --entrypoint sh "$IMAGE" -c 'claude --version' 2>/dev/null)"
  echo "Updated to $NEW_VERSION"
fi

# Fix ownership on the data volume so appuser can write credentials.
"$RUNTIME" run --rm --user root \
  --entrypoint sh \
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT" \
  "$IMAGE" -c "chown -R appuser:appuser $CLAUDE_DATA_MOUNT"

ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT"
  -e "CLAUDE_CONFIG_DIR=$CLAUDE_DATA_MOUNT"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ARGS+=(-e ANTHROPIC_API_KEY)
fi

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
