#!/bin/sh
# Installed as /usr/local/bin/xdg-open inside the container.
#
# Claude Code picks an ephemeral callback port at runtime.  This script:
#   1. Extracts that port from the redirect_uri in the auth URL
#   2. Starts a socat bridge inside the container: FIXED_PORT -> ephemeral port
#   3. Writes the original URL (unmodified) and the callback port to the IPC dir
#      so the host script can start a matching proxy on the host side
#
# When SUPER_CLAUDE_DEBUG=1, all events are timestamped to /tmp/sc-ipc/container.log

URL="$1"
FIXED_PORT=54321
IPC_DIR="/tmp/sc-ipc"
LOG="$IPC_DIR/container.log"

clog() {
    [ "${SUPER_CLAUDE_DEBUG:-0}" = "1" ] || return 0
    [ -d "$IPC_DIR" ] || return 0
    printf '[%s] %s\n' "$(date '+%T')" "$*" >> "$LOG"
}

clog "xdg-open called"
clog "url=$URL"

# Extract callback port from redirect_uri.
# Handles URL-encoded form (localhost%3APORT) and plain form (localhost:PORT).
CALLBACK_PORT=$(printf '%s' "$URL" | grep -o 'localhost%3A[0-9]*' | grep -o '[0-9]*$' | tr -d '[:space:]')
if [ -z "$CALLBACK_PORT" ]; then
    CALLBACK_PORT=$(printf '%s' "$URL" | grep -o 'localhost:[0-9]*' | grep -o '[0-9]*$' | tr -d '[:space:]')
fi

# Guard: ensure it's actually a number
case "$CALLBACK_PORT" in
    ''|*[!0-9]*) CALLBACK_PORT="" ;;
esac

clog "callback_port=$CALLBACK_PORT"

# Start container-side socat: fixed published port -> Claude's ephemeral callback port.
if [ -n "$CALLBACK_PORT" ] && [ "$CALLBACK_PORT" != "$FIXED_PORT" ]; then
    socat TCP-LISTEN:${FIXED_PORT},reuseaddr TCP:127.0.0.1:${CALLBACK_PORT} >/dev/null 2>&1 &
    SOCAT_PID=$!
    clog "socat bridge started (pid=$SOCAT_PID): :$FIXED_PORT -> :$CALLBACK_PORT"
else
    clog "WARNING: no callback port extracted, socat not started"
fi

# Always print to stderr so the user can copy it manually if needed
printf '\n[super-claude] Open this URL in your browser:\n  %s\n\n' "$URL" >&2

# Signal the host watcher: write callback port first (watcher reads URL last as trigger)
if [ -d "$IPC_DIR" ]; then
    [ -n "$CALLBACK_PORT" ] && printf '%s' "$CALLBACK_PORT" > "$IPC_DIR/callback-port"
    printf '%s' "$URL" > "$IPC_DIR/open-url"
    clog "ipc files written"
else
    clog "WARNING: IPC dir not mounted, cannot signal host"
fi
