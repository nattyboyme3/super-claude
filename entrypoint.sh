#!/bin/bash
# Runs at container startup before claude is launched.
# Writes a CLAUDE.md into the config dir so Claude has immediate context
# about its environment, installed tools, and constraints.

CLAUDE_MD="${CLAUDE_CONFIG_DIR:-/home/appuser/.claude}/CLAUDE.md"
mkdir -p "$(dirname "$CLAUDE_MD")"

cat > "$CLAUDE_MD" <<EOF
# super-claude environment

Container: Debian 12 (bookworm), non-root user "appuser" (no sudo, no systemd, no display server)
Host OS:   ${SUPER_CLAUDE_HOST_OS:-unknown}
Work dir:  $(pwd)  —  bind-mounted from host; edits are immediately live on the host filesystem
Persistent storage: /claude-data (Docker named volume, survives container restarts)

## Tools available
Downloads/archives : wget, curl, unzip, zip, xz-utils, bzip2
Text/data          : jq, rg (ripgrep), fdfind, patch, xxd, bc, envsubst
Editors/viewers    : vim, less, tree
Build              : gcc, g++, make, cmake, pkg-config
Database           : sqlite3
Python             : python3 (3.11), pip3, python3-venv, uv, uvx
                     To use a different Python version: uv python install 3.12 && uv venv --python 3.12
Network/SSH        : ssh, rsync, nc, dig, ping
System             : ps, lsof, file, shellcheck, parallel, entr
VCS                : git, gh (GitHub CLI)
Runtime            : node (LTS)

## Constraints
- Only the working dir and /claude-data persist; all other filesystem writes are lost on container exit
- Headless (no browser or display); internet available; port 54321 forwarded to host
EOF

exec claude "$@"
