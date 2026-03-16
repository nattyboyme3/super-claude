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

ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v "$HOME/.claude.json:$CONTAINER_HOME/.claude.json"
  -v "$HOME/.claude:$CONTAINER_HOME/.claude"
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ARGS+=(-e ANTHROPIC_API_KEY)
fi

# On macOS, Claude Code stores OAuth credentials in the Keychain rather than
# a file. Extract them to a temp file so the container can authenticate.
CREDS_TMPFILE=""
cleanup() {
  [[ -n "$CREDS_TMPFILE" ]] && rm -f "$CREDS_TMPFILE"
}
trap cleanup EXIT

if [[ "$(uname)" == "Darwin" ]]; then
  CREDS_JSON="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)"
  if [[ -n "$CREDS_JSON" ]]; then
    CREDS_TMPFILE="$(mktemp)"
    chmod 600 "$CREDS_TMPFILE"
    echo "$CREDS_JSON" > "$CREDS_TMPFILE"
    ARGS+=(-v "$CREDS_TMPFILE:$CONTAINER_HOME/.claude/.credentials.json")
  fi
fi

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
