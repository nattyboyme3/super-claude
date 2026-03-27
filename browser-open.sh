#!/bin/sh
# Installed as /usr/local/bin/xdg-open inside the container.
#
# Claude Code picks an ephemeral callback port at runtime.  This script:
#   1. Extracts that port from the redirect_uri in the auth URL
#   2. Starts a socat bridge inside the container: FIXED_PORT -> ephemeral port
#      (FIXED_PORT is published to the host via docker -p so Docker can forward
#       traffic from the host-side proxy into the container)
#   3. Writes the original URL (unmodified) and the callback port to the IPC dir
#      so the host script can start a matching proxy on the host side
#
# The host script then listens on the original callback port, forwarding through
# FIXED_PORT into the container — the browser uses the unmodified URL and
# Claude's server sees exactly the Host header it registered.

URL="$1"
FIXED_PORT=54321

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

# Start container-side socat: fixed published port -> Claude's ephemeral callback port.
# No URL rewriting needed — the host-side proxy handles the routing transparently.
if [ -n "$CALLBACK_PORT" ] && [ "$CALLBACK_PORT" != "$FIXED_PORT" ]; then
    socat TCP-LISTEN:${FIXED_PORT},reuseaddr TCP:127.0.0.1:${CALLBACK_PORT} >/dev/null 2>&1 &
fi

# Always print to stderr so the user can copy it manually if needed
printf '\n[super-claude] Open this URL in your browser:\n  %s\n\n' "$URL" >&2

# Signal the host watcher: write callback port first (watcher reads URL last as trigger)
if [ -d /tmp/sc-ipc ]; then
    [ -n "$CALLBACK_PORT" ] && printf '%s' "$CALLBACK_PORT" > /tmp/sc-ipc/callback-port
    printf '%s' "$URL" > /tmp/sc-ipc/open-url
fi
