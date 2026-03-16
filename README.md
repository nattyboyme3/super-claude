# super-claude

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with `--dangerously-skip-permissions` inside an isolated Docker container, so you can let it work autonomously without it prompting for every file write or shell command.

## How it works

The script launches [`ghcr.io/gendosu/claude-code-docker`](https://github.com/gendosu/claude-code-docker) — a pre-built image with Claude Code and Node.js 22 installed — and:

- Mounts your current working directory into the container at the same path
- Passes your host Claude credentials into the container for authentication
- Runs `claude --dangerously-skip-permissions`

Your files are edited directly on the host via the volume mount, so there's nothing to copy in or out.

## Prerequisites

- A supported container runtime (see below)
- Claude Code authenticated on your host machine (run `claude` once to log in if you haven't)

## Supported container runtimes

The script auto-detects whichever of these is available, in this order:

1. **Docker Desktop** — `brew install --cask docker-desktop`
2. **Apple Container** (Apple Silicon + macOS 15+ only) — `brew install container`
3. **Rancher Desktop** — `brew install --cask rancher` or [rancherdesktop.io](https://rancherdesktop.io)

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

**Claude.ai subscription (OAuth)** — the default. On macOS, Claude Code stores OAuth tokens in the Keychain rather than a plain file. The script extracts them automatically using the macOS `security` command, writes them to a `chmod 600` temp file, mounts it into the container as `~/.claude/.credentials.json`, and deletes it on exit. No manual setup needed.

**API key** — if `ANTHROPIC_API_KEY` is set in your environment, it will be passed into the container:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
super-claude
```

## A note on `--dangerously-skip-permissions`

This flag tells Claude Code to skip all permission prompts — it won't ask before writing files, running shell commands, etc. Running it inside Docker limits the blast radius to the mounted project directory, which is why this combination is the recommended approach for autonomous use.

Never run `--dangerously-skip-permissions` directly on your host machine.
