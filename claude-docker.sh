#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/nattyboyme3/super-claude:latest"
WORKDIR="$(pwd)"

CLAUDE_DATA_MOUNT="/claude-data"
CLAUDE_DATA_VOLUME="super-claude-data"

# ---------------------------------------------------------------------------
# Debug logging — enable with: super-claude --debug [args...]
# Log is written to ~/.super-claude-debug.log and also echoed to stderr.
# ---------------------------------------------------------------------------
DEBUG=0
DEBUG_LOG="$HOME/.super-claude-debug.log"
PASSTHROUGH_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--debug" ]]; then
    DEBUG=1
  else
    PASSTHROUGH_ARGS+=("$arg")
  fi
done
set -- "${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}"

dlog() {
  [[ "$DEBUG" == "0" ]] && return
  printf '[%s] %s\n' "$(date '+%T.%3N')" "$*" | tee -a "$DEBUG_LOG" >&2
}

if [[ "$DEBUG" == "1" ]]; then
  : > "$DEBUG_LOG"
  dlog "=== super-claude debug session ==="
  dlog "image=$IMAGE"
  dlog "workdir=$WORKDIR"
fi

# ---------------------------------------------------------------------------
# Container runtime detection
# ---------------------------------------------------------------------------
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

dlog "runtime=$RUNTIME"

# ---------------------------------------------------------------------------
# IPC dir for browser URL / OAuth callback passthrough.
# On macOS /tmp is a symlink to /private/tmp; Docker Desktop resolves bind
# mounts against the real path, so we must use /private/tmp explicitly.
# ---------------------------------------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
  IPC_DIR="/private/tmp/super-claude-ipc-$$"
else
  IPC_DIR="/tmp/super-claude-ipc-$$"
fi
mkdir -p "$IPC_DIR"
dlog "ipc_dir=$IPC_DIR"

WATCHER_PID=""

cleanup() {
  if [[ -f "$IPC_DIR/proxy.pid" ]]; then
    kill "$(cat "$IPC_DIR/proxy.pid")" 2>/dev/null || true
  fi
  [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null || true
  # Flush container log into debug log before removing IPC dir
  if [[ "$DEBUG" == "1" ]] && [[ -f "$IPC_DIR/container.log" ]]; then
    while IFS= read -r line; do
      printf '[container] %s\n' "$line" >> "$DEBUG_LOG"
    done < "$IPC_DIR/container.log"
  fi
  rm -rf "$IPC_DIR"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Host-side OAuth proxy script — written to IPC dir so the watcher can use
# it without any extra files in the repo.  Logs to debug log if provided.
# ---------------------------------------------------------------------------
cat > "$IPC_DIR/oauth-proxy.py" << 'PYEOF'
import socket, threading, sys, os
from datetime import datetime

log_file = sys.argv[3] if len(sys.argv) > 3 else None

def dlog(msg):
    if not log_file:
        return
    with open(log_file, 'a') as f:
        f.write(f'[{datetime.now().strftime("%H:%M:%S.%f")[:12]}] proxy: {msg}\n')

def relay(src, dst, direction):
    total = 0
    try:
        while True:
            data = src.recv(4096)
            if not data:
                dlog(f'{direction} EOF after {total} bytes')
                break
            dst.sendall(data)
            total += len(data)
            dlog(f'{direction} {len(data)} bytes ({total} total)')
    except Exception as e:
        dlog(f'{direction} relay ended after {total} bytes: {e}')
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
dlog(f'listening on :{listen_port}, will forward to :{target_port}')

conn, addr = server.accept()
dlog(f'accepted connection from {addr}')

target = socket.socket()
target.connect(('127.0.0.1', target_port))
dlog(f'connected to :{target_port}')

t1 = threading.Thread(target=relay, args=(conn, target, 'browser->claude'), daemon=True)
t2 = threading.Thread(target=relay, args=(target, conn, 'claude->browser'), daemon=True)
t1.start()
t2.start()
t1.join()
t2.join()
dlog('proxy done')

# Signal xdg-open in the container to unblock and return, which lets
# Claude proceed normally after the OAuth callback completes.
ipc_dir = os.path.dirname(os.path.abspath(__file__))
try:
    open(os.path.join(ipc_dir, 'oauth-done'), 'w').close()
    dlog('wrote oauth-done signal')
except Exception as e:
    dlog(f'could not write oauth-done: {e}')
PYEOF

# ---------------------------------------------------------------------------
# Host browser opener
# ---------------------------------------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
  HOST_OPEN="open"
else
  HOST_OPEN="xdg-open"
fi

# ---------------------------------------------------------------------------
# Background watcher: detects URLs + callback ports written by the container's
# xdg-open shim, starts the host-side proxy, then opens the browser.
# Also relays container log lines to the debug log in real time.
# ---------------------------------------------------------------------------
(
  CONTAINER_LOG_POS=0
  while true; do

    # Relay any new container log lines to the debug log
    if [[ "$DEBUG" == "1" ]] && [[ -f "$IPC_DIR/container.log" ]]; then
      LINES=$(wc -l < "$IPC_DIR/container.log")
      if (( LINES > CONTAINER_LOG_POS )); then
        tail -n "+$((CONTAINER_LOG_POS + 1))" "$IPC_DIR/container.log" | \
          while IFS= read -r line; do
            printf '[%s] [container] %s\n' "$(date '+%T.%3N')" "$line" >> "$DEBUG_LOG"
          done
        CONTAINER_LOG_POS=$LINES
      fi
    fi

    if [[ -f "$IPC_DIR/open-url" ]]; then
      URL="$(cat "$IPC_DIR/open-url")"
      rm -f "$IPC_DIR/open-url"
      dlog "open-url received"

      if [[ -f "$IPC_DIR/callback-port" ]]; then
        CALLBACK_PORT="$(cat "$IPC_DIR/callback-port")"
        rm -f "$IPC_DIR/callback-port"
        dlog "callback-port=$CALLBACK_PORT"

        if [[ -n "$CALLBACK_PORT" ]]; then
          PROXY_ARGS=("$CALLBACK_PORT" 54321)
          [[ "$DEBUG" == "1" ]] && PROXY_ARGS+=("$DEBUG_LOG")
          python3 "$IPC_DIR/oauth-proxy.py" "${PROXY_ARGS[@]}" &
          echo $! > "$IPC_DIR/proxy.pid"
          dlog "host proxy started (pid=$!), listening on :$CALLBACK_PORT"
        fi
      fi

      if [[ -n "$URL" ]]; then
        dlog "opening browser: $URL"
        "$HOST_OPEN" "$URL" 2>/dev/null || true
        dlog "browser open command returned"
      fi
    fi

    sleep 0.3
  done
) &
WATCHER_PID=$!
dlog "watcher started (pid=$WATCHER_PID)"

# ---------------------------------------------------------------------------
# Pull image if newer version available
# ---------------------------------------------------------------------------
dlog "checking for image updates"
CURRENT_ID="$("$RUNTIME" inspect --format='{{.Id}}' "$IMAGE" 2>/dev/null || true)"
"$RUNTIME" pull --quiet "$IMAGE"
NEW_ID="$("$RUNTIME" inspect --format='{{.Id}}' "$IMAGE")"
if [[ "$CURRENT_ID" != "$NEW_ID" ]]; then
  NEW_VERSION="$("$RUNTIME" run --rm --entrypoint sh "$IMAGE" -c 'claude --version' 2>/dev/null)"
  echo "Updated to $NEW_VERSION"
  dlog "image updated to $NEW_VERSION"
fi

# ---------------------------------------------------------------------------
# Fix volume/IPC dir ownership from the Linux side
# ---------------------------------------------------------------------------
dlog "fixing volume permissions"
"$RUNTIME" run --rm --user root \
  --entrypoint sh \
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT" \
  -v "$IPC_DIR:/tmp/sc-ipc" \
  "$IMAGE" -c "chown -R appuser:appuser $CLAUDE_DATA_MOUNT && chmod 777 /tmp/sc-ipc"
dlog "permissions fixed, launching container"

# ---------------------------------------------------------------------------
# Launch Claude
# ---------------------------------------------------------------------------
ARGS=(
  run -it --rm
  --workdir "$WORKDIR"
  -v "$WORKDIR:$WORKDIR"
  -v "$CLAUDE_DATA_VOLUME:$CLAUDE_DATA_MOUNT"
  -e "CLAUDE_CONFIG_DIR=$CLAUDE_DATA_MOUNT"
  -v "$IPC_DIR:/tmp/sc-ipc"
  -p 54321:54321
)

[[ "$DEBUG" == "1" ]]             && ARGS+=(-e SUPER_CLAUDE_DEBUG=1)
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && ARGS+=(-e ANTHROPIC_API_KEY)
ARGS+=(-e "SUPER_CLAUDE_HOST_OS=$(uname -s)/$(uname -m)")

"$RUNTIME" "${ARGS[@]}" "$IMAGE" --dangerously-skip-permissions "$@"
