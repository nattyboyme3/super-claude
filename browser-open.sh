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
# Pre-connects to Claude's server immediately on both 127.0.0.1 (IPv4) and ::1 (IPv6)
# because node:lts-bookworm-slim may bind 'localhost' to ::1, making IPv4-only connects
# fail with ECONNREFUSED. Dumps /proc/net/tcp6 on give-up so we can see where Claude bound.
if [ -n "$CALLBACK_PORT" ] && [ "$CALLBACK_PORT" != "$FIXED_PORT" ]; then
    node -e "
const net = require('net');
const fs  = require('fs');
const FIXED = $FIXED_PORT, CB = $CALLBACK_PORT;
const debug = process.env.SUPER_CLAUDE_DEBUG === '1';
const log = msg => { if (debug) fs.appendFileSync('$LOG', '[bridge] ' + msg + '\n'); };

let held        = null;   // pre-established connection to Claude
let keepPreconn = true;   // keep re-connecting until browser arrives

function splice(a, b) {
  a.pipe(b); b.pipe(a);
  a.on('error', () => b.destroy());
  b.on('error', () => a.destroy());
  a.on('close', () => log('client side closed'));
  b.on('close', () => log('claude side closed'));
}

function preConnect(retries) {
  // Try both IPv4 and IPv6 loopback simultaneously; first to connect wins
  const addrs = ['127.0.0.1', '::1'];
  let failures = 0;
  let won = false;

  addrs.forEach(addr => {
    const t = net.createConnection(CB, addr);
    t.on('connect', () => {
      if (won) { t.destroy(); return; }
      won = true;
      log('pre-connected to ' + addr + ':' + CB + ' (retries left=' + retries + ')');
      held = t;
      t.on('close', () => {
        if (held === t) { held = null; log('pre-connection closed'); }
        // Re-establish immediately so there's always a fresh connection ready
        if (keepPreconn) setTimeout(() => preConnect(25), 50);
      });
    });
    t.on('error', e => {
      log('pre-connect ' + addr + ':' + CB + ' error: ' + e.message);
      if (won) return;
      failures++;
      if (failures < addrs.length) return; // wait for the other address to resolve
      // Both addresses failed this round
      if (retries > 0) {
        setTimeout(() => preConnect(retries - 1), 200);
      } else {
        log('gave up connecting to :' + CB + ' on both 127.0.0.1 and ::1');
        // Dump listening sockets so we can see where Claude actually bound
        ['tcp', 'tcp6'].forEach(f => {
          try { log('/proc/net/' + f + ':\n' + fs.readFileSync('/proc/net/' + f, 'utf8')); } catch(_) {}
        });
      }
    });
  });
}
preConnect(25); // retry for up to ~5 seconds

net.createServer(client => {
  log('browser client arrived');
  keepPreconn = false;  // stop background pre-connect loop
  if (held && !held.destroyed) {
    log('using pre-established connection');
    splice(client, held);
    held = null;
  } else {
    log('held connection not ready, connecting on-demand');
    const addrs = ['::1', '127.0.0.1'];
    let won = false;
    let failures = 0;
    addrs.forEach(addr => {
      const t = net.createConnection(CB, addr);
      t.on('connect', () => {
        if (won) { t.destroy(); return; }
        won = true;
        log('on-demand connected to ' + addr + ':' + CB);
        splice(client, t);
      });
      t.on('error', e => {
        log('on-demand connect ' + addr + ':' + CB + ' error: ' + e.message);
        if (won) return;
        failures++;
        if (failures === addrs.length) {
          log('on-demand connect failed on all addresses, destroying client');
          client.destroy();
        }
      });
    });
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
# server when xdg-open exits. Block until the host proxy signals completion
# (writes oauth-done to the IPC dir), or 120-second safety timeout.
clog "xdg-open blocking until callback completes (max 120s)"
i=0
while [ $i -lt 240 ]; do
    [ -f "$IPC_DIR/oauth-done" ] && break
    sleep 0.5
    i=$((i + 1))
done
clog "xdg-open unblocking (i=$i, done=$([ -f "$IPC_DIR/oauth-done" ] && echo yes || echo no))"
rm -f "$IPC_DIR/oauth-done"
