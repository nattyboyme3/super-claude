# super-claude

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with `--dangerously-skip-permissions` inside an isolated Docker container, so you can let it work autonomously without it prompting for every file write or shell command.

## How it works

The script launches [`ghcr.io/gendosu/claude-code-docker`](https://github.com/gendosu/claude-code-docker) — a pre-built image with Claude Code and Node.js 22 installed — and:

- Mounts your current working directory into the container at the same path
- Passes your host Claude credentials into the container for authentication
- Runs `claude --dangerously-skip-permissions`

Your files are edited directly on the host via the volume mount, so there's nothing to copy in or out.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- Claude Code authenticated on your host machine (run `claude` once to log in if you haven't)

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/nattyboyme3/super-claude.git
```

### 2. Make the script executable

```bash
chmod +x super-claude/claude-docker.sh
```

### 3. Alias it as `super-claude`

Add this to your `~/.zshrc`, `~/.bashrc`, or equivalent:

```bash
alias super-claude='/path/to/super-claude/claude-docker.sh'
```

Replace `/path/to/super-claude` with the actual path where you cloned the repo. Then reload your shell:

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

The script supports two auth methods:

**Claude.ai subscription (OAuth)** — the default. Your host credentials at `~/.claude.json` and `~/.claude/` are mounted read-write into the container automatically. No extra setup needed.

**API key** — if `ANTHROPIC_API_KEY` is set in your environment, it will be passed into the container:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
super-claude
```

## A note on `--dangerously-skip-permissions`

This flag tells Claude Code to skip all permission prompts — it won't ask before writing files, running shell commands, etc. Running it inside Docker limits the blast radius to the mounted project directory, which is why this combination is the recommended approach for autonomous use.

Never run `--dangerously-skip-permissions` directly on your host machine.
