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

# Initialise the home-dir volume on first use:
#   - Seed it with the image's /home/appuser skeleton (so .nodenv, .bashrc, etc.
#     are present) if it hasn't been seeded yet (no .bashrc = fresh/old volume).
#   - Fix ownership so appuser (uid 1001) can write to it.
# Mounting at /mnt/home lets us still see the image's original /home/appuser
# for the cp, then the main run mounts the volume at /home/appuser proper.
"$RUNTIME" run --rm --user root \
  --entrypoint sh \
  -v super-claude-home:/mnt/home \
  "$IMAGE" -c '
    [ -f /mnt/home/.bashrc ] || cp -a /home/appuser/. /mnt/home/
    chown -R appuser:appuser /mnt/home
  '

ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v super-claude-home:"$CONTAINER_HOME"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ARGS+=(-e ANTHROPIC_API_KEY)
fi

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
