#!/bin/sh
# Installed as /usr/local/bin/xdg-open inside the container.
# Passes URLs to the host via a shared IPC directory so the host script
# can open them in the real browser.  Always prints to stderr as a fallback.

URL="$1"

# Always visible in the terminal so the user can copy it manually if needed
printf '\n[super-claude] Open this URL in your browser:\n  %s\n\n' "$URL" >&2

# Signal the host watcher if the IPC dir is mounted
if [ -d /tmp/sc-ipc ]; then
    printf '%s' "$URL" > /tmp/sc-ipc/open-url
fi
