#!/bin/sh
# Installed as /usr/local/bin/xdg-open inside the container.
#
# Claude Code picks an ephemeral callback port at runtime.  This script:
#   1. Extracts that port from the redirect_uri in the auth URL
#   2. Starts a Node.js TCP bridge: FIXED_PORT -> ephemeral port
#      (handles multiple connections, so Docker port probes don't consume it)
#   3. Writes the original URL and callback port to the IPC dir so the
#      host script can start a matching host-side proxy
#
# When SUPER_CLAUDE_DEBUG=1, events are timestamped to /tmp/sc-ipc/container.log

URL="$1"
FIXED_PORT=54321
IPC_DIR="/tmp/sc-ipc"
LOG="$IPC_DIR/container.log"

clog() {
    [ -d "$IPC_DIR" ] || return 0
    [ "${SUPER_CLAUDE_DEBUG:-0}" = "1" ] || return 0
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

# Start a Node.js TCP bridge: fixed published port -> Claude's ephemeral callback port.
# Using Node.js (not socat) so multiple connections are handled natively — a Docker
# Desktop port probe won't consume the bridge's single connection slot.
if [ -n "$CALLBACK_PORT" ] && [ "$CALLBACK_PORT" != "$FIXED_PORT" ]; then
    node -e "
const net = require('net');
const FIXED = $FIXED_PORT, CB = $CALLBACK_PORT;
const debug = process.env.SUPER_CLAUDE_DEBUG === '1';
const log = msg => { if (debug) require('fs').appendFileSync('$LOG', '[bridge] ' + msg + '\n'); };

// Pre-connect to Claude's callback server IMMEDIATELY so the connection
// exists before Claude's server stops accepting new ones (~5s timeout).
// Node.js server.close() stops accepting NEW connections but keeps existing
// ones alive -- our pre-established socket survives the listener shutdown.
let held = null;      // pre-established connection to Claude
let waiting = null;   // browser client that arrived before held was ready

function splice(a, b) {
  a.pipe(b); b.pipe(a);
  a.on('error', () => b.destroy());
  b.on('error', () => a.destroy());
  a.on('close', () => log('client side closed'));
  b.on('close', () => log('claude side closed'));
}

function preConnect(retries) {
  const t = net.createConnection(CB, '127.0.0.1');
  t.on('connect', () => {
    log('pre-connected to :' + CB + ' (held open, retries left=' + retries + ')');
    held = t;
    if (waiting) { log('wiring waiting client'); splice(waiting, held); waiting = null; held = null; }
  });
  t.on('error', e => {
    log('pre-connect error: ' + e.message + ' (retries left=' + retries + ')');
    if (retries > 0) setTimeout(() => preConnect(retries - 1), 200);
    else log('gave up pre-connecting');
  });
  t.on('close', () => { if (held === t) held = null; log('pre-connection closed'); });
}
preConnect(25); // retry for up to ~5 seconds

net.createServer(client => {
  log('browser client arrived');
  if (held && !held.destroyed) {
    log('using pre-established connection');
    splice(client, held);
    held = null;
  } else {
    log('held connection not ready, queuing client');
    waiting = client;
  }
}).listen(FIXED, '0.0.0.0', () => log('bridge ready :' + FIXED + ' -> :' + CB));
" 2>>"$LOG" &
    clog "node bridge started (pid=$!): :$FIXED_PORT -> :$CALLBACK_PORT"
else
    clog "WARNING: no callback port extracted, bridge not started"
fi

# Always print to stderr so the user can copy it manually if needed
printf '\n[super-claude] Open this URL in your browser:\n  %s\n\n' "$URL" >&2

# Signal the host watcher: write callback port first, URL last (URL is the trigger)
if [ -d "$IPC_DIR" ]; then
    [ -n "$CALLBACK_PORT" ] && printf '%s' "$CALLBACK_PORT" > "$IPC_DIR/callback-port"
    printf '%s' "$URL" > "$IPC_DIR/open-url"
    clog "ipc files written"
else
    clog "WARNING: IPC dir not mounted, cannot signal host"
fi

# Do NOT return immediately. Claude starts a shutdown timer for its OAuth callback
# server when xdg-open exits. A real browser launcher takes several seconds to
# return; ours exits in ~50ms, which causes Claude to shut down the server before
# the browser can complete the OAuth redirect.
#
# Block here until the host proxy signals completion (writes 'done' to the IPC dir),
# or until a 120-second safety timeout, whichever comes first.
clog "xdg-open blocking until callback completes (max 120s)"
i=0
while [ $i -lt 240 ]; do
    [ -f "$IPC_DIR/oauth-done" ] && break
    sleep 0.5
    i=$((i + 1))
done
clog "xdg-open unblocking (i=$i, done=$([ -f "$IPC_DIR/oauth-done" ] && echo yes || echo no))"
rm -f "$IPC_DIR/oauth-done"
