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

# IPC dir for browser URL passthrough.
# The container's fake xdg-open writes URLs here; the watcher below reads
# them and opens the real browser on the host.
# Use /tmp (not mktemp -d) so it's always within Docker Desktop's file-share
# allowlist on macOS; suffix with PID to avoid collisions.
IPC_DIR="/tmp/super-claude-ipc-$$"
mkdir -p "$IPC_DIR"
WATCHER_PID=""

cleanup() {
  # Kill the host-side OAuth proxy if one was started
  if [[ -f "$IPC_DIR/proxy.pid" ]]; then
    kill "$(cat "$IPC_DIR/proxy.pid")" 2>/dev/null || true
  fi
  [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null || true
  rm -rf "$IPC_DIR"
}
trap cleanup EXIT INT TERM

# Write the host-side OAuth proxy script to the IPC dir.
# It listens on the callback port the browser expects, and forwards traffic
# through Docker's published port (54321) into the container.
cat > "$IPC_DIR/oauth-proxy.py" << 'PYEOF'
import socket, threading, sys

def relay(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except:
        pass
    finally:
        for s in (src, dst):
            try:
                s.close()
            except:
                pass

listen_port = int(sys.argv[1])
target_port = int(sys.argv[2])

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', listen_port))
server.listen(1)
conn, _ = server.accept()
target = socket.socket()
target.connect(('127.0.0.1', target_port))

t1 = threading.Thread(target=relay, args=(conn, target), daemon=True)
t2 = threading.Thread(target=relay, args=(target, conn), daemon=True)
t1.start()
t2.start()
t1.join()
t2.join()
PYEOF

# Detect the host's browser-open command
if [[ "$(uname)" == "Darwin" ]]; then
  HOST_OPEN="open"
else
  HOST_OPEN="xdg-open"
fi

# Background watcher: polls every 0.3 s for a URL written by xdg-open inside
# the container.  If a callback port was also signalled, starts a host-side
# TCP proxy (callback_port -> 54321) so the browser's OAuth redirect reaches
# the container without any URL rewriting.
(
  while true; do
    if [[ -f "$IPC_DIR/open-url" ]]; then
      URL="$(cat "$IPC_DIR/open-url")"
      rm -f "$IPC_DIR/open-url"

      # Start host-side proxy if the container signalled a callback port
      if [[ -f "$IPC_DIR/callback-port" ]]; then
        CALLBACK_PORT="$(cat "$IPC_DIR/callback-port")"
        rm -f "$IPC_DIR/callback-port"
        if [[ -n "$CALLBACK_PORT" ]]; then
          python3 "$IPC_DIR/oauth-proxy.py" "$CALLBACK_PORT" 54321 &
          echo $! > "$IPC_DIR/proxy.pid"
        fi
      fi

      [[ -n "$URL" ]] && "$HOST_OPEN" "$URL" 2>/dev/null || true
    fi
    sleep 0.3
  done
) &
WATCHER_PID=$!

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
  -v "$IPC_DIR:/tmp/sc-ipc"
  -p 54321:54321
)

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ARGS+=(-e ANTHROPIC_API_KEY)
fi

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
