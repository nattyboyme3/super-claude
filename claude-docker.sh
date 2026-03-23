#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/gendosu/claude-code-docker:latest"
WORKDIR="$(pwd)"
CONTAINER_HOME="/home/appuser"

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

# Fix volume ownership: Docker creates named volumes as root-owned, but the
# container runs as appuser (uid 1001). Chown the volume on every launch —
# it's a no-op if ownership is already correct.
"$RUNTIME" run --rm --user root \
  --entrypoint sh \
  -v super-claude-credentials:"$CONTAINER_HOME/.claude" \
  "$IMAGE" -c "chown -R appuser:appuser $CONTAINER_HOME/.claude"

ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v super-claude-credentials:"$CONTAINER_HOME/.claude"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ARGS+=(-e ANTHROPIC_API_KEY)
fi

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
