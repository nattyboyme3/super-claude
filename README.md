# super-claude

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with `--dangerously-skip-permissions` inside an isolated Docker container, so you can let it work autonomously without it prompting for every file write or shell command.

## How it works

The script pulls [`ghcr.io/nattyboyme3/super-claude:latest`](https://github.com/nattyboyme3/super-claude) — a pre-built image with Claude Code installed via the official native installer — and:

- Mounts your current working directory into the container at the same path
- Uses a persistent Docker volume (`super-claude-data`) to store Claude credentials and config across runs, via `CLAUDE_CONFIG_DIR`
- Runs `claude --dangerously-skip-permissions`
- Auto-pulls the latest image on every launch and prints the new version if it changed

Your files are edited directly on the host via the volume mount, so there's nothing to copy in or out.

### Browser OAuth login

When Claude Code needs to authenticate, it opens a browser window. Because Claude is running inside a container, the script handles this automatically:

1. The container detects the OAuth URL and signals the host
2. The host script opens the URL in your default browser
3. A TCP proxy routes the OAuth callback from your browser back into the container
4. Claude completes authentication and proceeds normally

The URL is also printed to the terminal so you can open it manually if needed.

## Prerequisites

- A supported container runtime (see below)

## Supported container runtimes

The script auto-detects whichever of these is available, in this order:

1. **Docker** / **Docker Desktop** — `brew install --cask docker-desktop`
2. **Apple Container** (Apple Silicon + macOS 15+ only) — `brew install container`
3. **nerdctl** / **Rancher Desktop** — `brew install --cask rancher` or [rancherdesktop.io](https://rancherdesktop.io)

If none is found, the script prints install instructions and exits.

## Setup

### One-liner install (macOS, zsh)

```bash
git clone https://github.com/nattyboyme3/super-claude.git ~/super-claude && chmod +x ~/super-claude/claude-docker.sh && echo 'alias super-claude="$HOME/super-claude/claude-docker.sh"' >> ~/.zshrc && source ~/.zshrc
```

This clones the repo to `~/super-claude`, makes the script executable, and adds the alias to your `~/.zshrc`. If you use bash, replace `~/.zshrc` with `~/.bashrc`.

### Manual setup

1. Clone the repo:
   ```bash
   git clone https://github.com/nattyboyme3/super-claude.git ~/super-claude
   chmod +x ~/super-claude/claude-docker.sh
   ```

2. Add to your `~/.zshrc` or `~/.bashrc`:
   ```bash
   alias super-claude="$HOME/super-claude/claude-docker.sh"
   ```

3. Reload your shell:
   ```bash
   source ~/.zshrc   # or source ~/.bashrc
   ```

## Usage

Navigate to any project directory and run:

```bash
cd ~/your-project
super-claude
```

You can also pass an initial prompt:

```bash
super-claude "refactor the auth module to use JWT"
```

Any additional arguments are forwarded directly to `claude`.

## Authentication

Credentials are stored in a named Docker volume (`super-claude-data`) that persists between runs.

**First run on a new machine:** Claude Code will open your browser to authenticate via OAuth. Complete the login flow and Claude will save credentials to the volume automatically.

**Subsequent runs:** credentials are reused — no login needed.

**Different machine:** each machine has its own volume, so you'll log in once per machine.

**To log out or switch accounts:**
```bash
docker volume rm super-claude-data
```

**API key** — if `ANTHROPIC_API_KEY` is set in your environment, it will be passed into the container instead:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
super-claude
```

## Troubleshooting

### Debug mode

Pass `--debug` to enable detailed timestamped logging:

```bash
super-claude --debug
```

This writes a log to `~/.super-claude-debug.log` covering:

- Container runtime and image version
- OAuth URL detection and browser open events
- TCP bridge connections (container side) and proxy relay (host side)
- IPC signal files written/read between host and container

The `--debug` flag is stripped before being passed to `claude`, so Claude itself won't see it.

### OAuth callback issues

If the browser shows a "connection refused" error during login, check the debug log for lines tagged `[bridge]` (container TCP bridge) and `proxy:` (host relay). The most common cause is a firewall or VPN blocking loopback connections on port `54321`.

## A note on `--dangerously-skip-permissions`

This flag tells Claude Code to skip all permission prompts — it won't ask before writing files, running shell commands, etc. Running it inside Docker limits the blast radius to the mounted project directory, which is why this combination is the recommended approach for autonomous use.

Never run `--dangerously-skip-permissions` directly on your host machine.
