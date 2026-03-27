#!/bin/sh
# Installed as /usr/local/bin/xdg-open inside the container.
#
# For OAuth login URLs, Claude Code picks an ephemeral callback port that
# isn't published to the host.  This script:
#   1. Extracts that ephemeral port from the redirect_uri in the URL
#   2. Starts a socat bridge: fixed published port -> ephemeral callback port
#   3. Rewrites the URL to reference the fixed port instead
#   4. Signals the host watcher via the shared IPC dir so the browser opens
#
# The fixed port (OAUTH_PROXY_PORT) must match the -p flag in claude-docker.sh.

URL="$1"
OAUTH_PROXY_PORT=54321

# Extract the OAuth callback port from redirect_uri.
# The parameter value may be URL-encoded (localhost%3APORT) or plain (localhost:PORT).
CALLBACK_PORT=$(printf '%s' "$URL" | grep -o 'localhost%3A[0-9]*' | grep -o '[0-9]*$')
if [ -z "$CALLBACK_PORT" ]; then
    CALLBACK_PORT=$(printf '%s' "$URL" | grep -o 'localhost:[0-9]*' | grep -o '[0-9]*$')
fi

# If we found an ephemeral port, bridge it to the fixed published port via socat
if [ -n "$CALLBACK_PORT" ] && [ "$CALLBACK_PORT" != "$OAUTH_PROXY_PORT" ]; then
    socat TCP-LISTEN:${OAUTH_PROXY_PORT},fork,reuseaddr TCP:127.0.0.1:${CALLBACK_PORT} >/dev/null 2>&1 &
    # Rewrite the URL so the browser callback hits the fixed port
    URL=$(printf '%s' "$URL" \
        | sed "s/localhost%3A${CALLBACK_PORT}/localhost%3A${OAUTH_PROXY_PORT}/g" \
        | sed "s/localhost:${CALLBACK_PORT}/localhost:${OAUTH_PROXY_PORT}/g")
fi

# Always print to stderr so the user can copy it manually if needed
printf '\n[super-claude] Open this URL in your browser:\n  %s\n\n' "$URL" >&2

# Signal the host watcher if the IPC dir is mounted
if [ -d /tmp/sc-ipc ]; then
    printf '%s' "$URL" > /tmp/sc-ipc/open-url
fi
