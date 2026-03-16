#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/gendosu/claude-code-docker:latest"
WORKDIR="$(pwd)"
CONTAINER_HOME="/home/appuser"

DOCKER_ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v "$HOME/.claude.json:$CONTAINER_HOME/.claude.json"
  -v "$HOME/.claude:$CONTAINER_HOME/.claude"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  DOCKER_ARGS+=(-e ANTHROPIC_API_KEY)
fi

docker "${DOCKER_ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
