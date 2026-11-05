# agent-container — AI Coding Agent Container Harness

**Run Claude Code and OpenCode in a limited, disposable, persistent container with a single command.**

This project is a small Podman-based harness for running AI coding-agent CLIs (currently supporting Claude Code and OpenCode CLI) inside a Fedora container. Your project hierarchy is mounted into the container as its working directory, while agent sessions, configuration, and history persist on the host under `aicontainer-config/` — so you can close the terminal, reattach later, and keep working.

Think of it as a reproducible dev environment for AI coding agents: the container provides the tools and CLI updates, your host keeps the state.

---

## Features

- **One-command launch:** `./claude` or `./opencode` builds and runs the container automatically
- **Persistent sessions:** config, sessions, and state survive container removal via bind mounts
- **Session resume by default:** both agents start with `--continue` unless you force a new session
- **Weekly auto-update:** CLIs and container image rebuild are refreshed automatically when older than 7 days
- **Screen-friendly:** runs inside `screen` by default so the session survives closing your terminal window
- **Per-project-set customization:** each working directory has its own state storage in an auto-created directory `aicontainer-config/`. The project set's setup can be customized (with per set tools and configuration) by dropping a `Dockerfile` and/or `.env` files into the state storage directory - the `Dockerfile` layers on top of the default image, and the `.env` is loaded at runtime over the default configuration.
- **rootless Podman:** runs with `--userns=keep-id` and `:Z` SELinux relabeling

## Prerequisites

On your host you need:

- **Podman** (for building and running the container)
- **Screen** (optional, but recommended — used for attachable terminal sessions)
- An account / API key for the provider you want to use (e.g. AWS Bedrock, Anthropic, etc. — see [Configuration](#configuration))

The podman container is based on `fedora:latest`.

## Quick Start

Clone the repo (or copy these files to any directory), then configure your credentials **before** the first run:

```bash
# 1. Get the harness files
git clone <repo-url> agent-container
cd agent-container

# 2. Optional: for system-wide credentials - add your environment secrets to `default.conf`
cp default.conf.example default.conf
#    then edit default.conf and fill in your own tokens

# 3. Go to your project directory and launch an agent
cd ~/Documents/Projects
~/path/to/agent-container/claude
# or
~/path/to/agent-container/opencode

# 4. Work inside /home/aicode/Projects (your project directory)
#    Sessions persist under ./aicontainer-config/
```

> ⚠️  **Do not commit the `aicontainer-config/` directory this scripts create.** This contains provider credentials and local session state.

### Optional - "install" the agent container commands into the PATH of your user account

Locate your user's local executable directory (usually `~/.local/bin` or `~/bin`) and create symbolic links from the `start-container` command (like the local symbolic links). For example:

```
ln -s ${PWD}/start-container ~/.local/bin/opencode
ln -s ${PWD}/start-container ~/.local/bin/claude
```

## Usage

```bash
./claude [-r <base-dir>] [-s|-f] [-n] [-S] [-d] [extra args...]
./opencode [same options]
```

The three entry points (`start-container`, `claude`, `opencode`) are the same script. Behavior is selected by the **invocation name**

| Invoked as | Agent launched inside container |
|---|---|
| `./claude` (or `claude`) | Claude Code |
| `./opencode` (or `opencode`) | OpenCode |
| `./start-container` | Claude Code (default) |

### Options

| Flag | Description |
|---|---|
| `-r <base-dir>` | Mount `<base-dir>` as `/home/aicode/Projects` (the agent's working directory). Defaults to the directory containing the launcher script. Also used as the session name, and the location where `aicontainer-config/` and `.ssh/` are looked up. `~/` is expanded. |
| `-s` | Skip rebuilding the container image, even if stale |
| `-f` | Force rebuilding the container image, even if not stale |
| `-n` | Force a **new session** — do not pass `--continue` to the agent |
| `-S` | Do **not** wrap in `screen`. Session will not survive the terminal closing |
| `-d` | Enable `bash -x` debug tracing for the launcher script |
| `-h`, `-?` | Show usage |

Any additional arguments are forwarded to the container entrypoint.

### Examples

```bash
# Start Claude Code in the current directory (default)
./claude

# Start OpenCode in another project directory
./opencode -r ~/projects/my-app

# Force a fresh session and a fresh image build
./claude -n -f

# Skip screen (run in the current terminal)
./opencode -S

# Keep an old agent installation and do not upgrade
./claude -s
```

## How It Works

### Container image (`Dockerfile`)

The base image (`aicode:latest`) is built from `fedora:latest` and includes:

- `gitflow cargo npm awscli2 which procps-ng jq` (via `dnf`, with the `elegos/gitflow` COPR enabled)
- User `aicode` (uid/gid 1000) with passwordless `sudo`, and home directory at `/home/aicode`
- **Claude CLI** installed from `https://claude.ai/install.sh` (`CLAUDE_CONFIG_DIR=/home/aicode/.config/claude`)
- **OpenCode CLI** installed from `https://opencode.ai/v2/install`
- `default.conf` baked in as `/.env`
- An entrypoint script `docker-entrypoint.sh`
- Volumes: `/home/aicode/Projects` (work) and `/home/aicode/.config` (agent config)

### Entrypoint (`docker-entrypoint.sh`)

Runs inside the container on every start:

1. Loads `/.env` (your `default.conf`) and `$HOME/.config/.env` (per-project override) into the environment
2. Configures global Git identity from `GIT_EMAIL` / `GIT_NAME` if set
3. Weekly auto-update: if the marker file (`~/.config/claude_last_update` or `opencode_last_update`) is older than 7 days, runs `claude update` / `opencode update`
4. Launches the selected agent, resuming the previous session unless `-n` was specified

Default agent flags:

```bash
# Claude Code
claude --allow-dangerously-skip-permissions --dangerously-skip-permissions \
       --allowedTools "*" --permission-mode acceptEdits -n aicode [--continue]

# OpenCode
~/.opencode/bin/opencode --auto [--continue]
```

> These are deliberately permissive settings for an isolated container. Review them before using on sensitive projects — see [Security](#security).

### Host-side launcher (`start-container`)

On every run it:

1. Re-execs itself inside `screen` unless `-S` is specified or already inside screen
2. Creates `aicontainer-config/`, `aicontainer-config/opencode/shared/`, and `aicontainer-config/opencode/state/` if missing
3. Rebuilds the image `aicode:latest` if missing, ≥7 days old, or forced (`-f`); `-s` skips this entirely
4. If `<project>/aicontainer-config/Dockerfile` exists, builds a **project-specific image** `aicode-<session>:latest` on top of the base image
5. Runs the container with Podman (see mounts below)

### Persistent mounts

| Host path | Container path | Contents |
|---|---|---|
| `$rootdir/` (your project) | `/home/aicode/Projects` | Project files, agent working directory (`:Z`) |
| `$rootdir/aicontainer-config/` | `/home/aicode/.config` | Claude config, update markers, override files |
| `$rootdir/aicontainer-config/opencode/shared/` | `~/.local/share/opencode` | OpenCode session DB, snapshots, logs |
| `$rootdir/aicontainer-config/opencode/state/` | `~/.local/state/opencode` | Prompt history, locks |
| `$rootdir/.ssh/` (if present) | `~/.ssh/` (read-only) | SSH keys for git access |

After the run, everything your agent created persists on the host under `aicontainer-config/`. Removing the container does not remove your work — the container is run with `--rm`.

## Project Structure

```
agent-container/
├── Dockerfile              # Base container image definition
├── docker-entrypoint.sh    # In-container entrypoint (env, git identity, agent launch)
├── start-container         # Host-side launcher script (build + podman run)
├── claude -> start-container   # Symlink: launch Claude Code
├── opencode -> start-container # Symlink: launch OpenCode
├── default.conf.example    # Template for provider credentials (copy to claude-code.conf)
└── default.conf            # YOUR credentials — do not commit
```

## Configuration

### Provider credentials (`claude-code.conf`)

Edit `default.conf` (create it from `default.conf.example`). At container build time it is copied into the image as `/.env`. A typical Bedrock-based setup looks like:

```bash
AWS_BEARER_TOKEN_BEDROCK=<your-token>
CLAUDE_CODE_USE_BEDROCK=1
AWS_REGION=<your-region>

ANTHROPIC_MODEL=<your-model-id>
ANTHROPIC_SMALL_FAST_MODEL=<your-fast-model-id>
```

For other providers, set the environment variables your agent expects (e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `CLAUDE_CODE_USE_FOUNDRY=1`, `ANTHROPIC_FOUNDRY_*`). Only the last assignment of a variable wins — remove duplicate lines.

Rebuild the image after changing credentials (or run with `-f` once):

```bash
./claude -f
```

### Per-project override (`.env`)

You can add `aicontainer-config/.env` (same `KEY=value` format). It is sourced **after** `/.env` inside the container, so values there override the baked-in ones without rebuilding the image. Useful for per-project model selection or Git identity:

```bash
GIT_EMAIL="you@example.com"
GIT_NAME="Your Name"
ANTHROPIC_MODEL=...
```

### Git identity

The `Dockerfile` sets defaults:

```dockerfile
ENV GIT_EMAIL="agents-containers-harness@geek.co.il" GIT_NAME="Change Me!"
```

The entrypoint applies these (and/or your `.env` overrides) via `git config --global user.email` / `user.name` inside the container. Change them to your own name and email, ideally via `aicontainer-config/.env` rather than editing the `Dockerfile`.

### Customizing the image for a project

Place a `Dockerfile` in your project's `aicontainer-config/` directory. The launcher will build it as `aicode-<project-name>:latest` and use it instead of the base image, letting you install project-specific toolchains (e.g. language runtimes, linters, test tools).

## Security

Please read this before pointing the harness at sensitive projects:

- **Agents run with broad permissions:** Claude Code is launched with `--allow-dangerously-skip-permissions --dangerously-skip-permissions --allowedTools "*" --permission-mode acceptEdits`, and OpenCode with `--auto`. This is convenient in a sandbox but means the agent can edit files freely. Only run it on projects you trust.
- **Passwordless sudo inside the container:** the `aicode` user can `sudo` without a password. This is contained to the container, but reinforces that the container boundary is your security boundary.
- **Project directory is a bind mount:** the agent sees and can modify your entire project directory (it *is* your project). Review changes with `git diff` before committing.
- **Global secrets are baked into the image at build time:** `default.conf` becomes part of the image layers. Anyone with access to `podman images` / the image tarball can extract it. Prefer the `aicontainer-config/.env` override pattern for sensitive values, or use `podman secret` / mounted files in your own fork.
- **SSH keys** (if `$rootdir/.ssh` exists) are mounted read-only. Never mount `~/.aws`, cloud credentials, or other host secrets unless you intend the agent to use them.
- **Do not commit** `default.conf` or `aicontainer-config/` (sessions, snapshots, service credentials). The shipped `.gitignore` covers this — keep it.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Image not rebuilding after editing `Dockerfile` | Run with `-f` (`./claude -f`), or remove the stale `aicode:latest` image |
| Agent credentials not picked up | Check `default.conf` was created from the example and the image was rebuilt (`-f`). Verify with `./claude -d` |
| Session not resuming | You passed `-n` (new session) or `aicontainer-config/` was deleted. Drop `-n` to resume |
| `podman run` permission / SELinux errors | Ensure Podman is rootless-capable on your system and the `:Z` relabeling is supported; try on a regular (non-)`/home`-mounted) directory |
| Screen session lost / can't reattach | `screen -r` to list sessions; sessions are named `<cmd>_<project>_screen`. Use `-S` if you don't want screen |
| Update failures inside container | Delete `aicontainer-config/*_last_update` to force an update on next start, or run `claude update` / `opencode update` manually in the container |

For detailed diagnostics, run with `-d` for launcher-side tracing, or `podman logs <container-name>` if the container is still alive.

## License

This software is licensed under a BSD 3-clause style license. See `LICENSE` for details.

---

*Contributions and improvements welcome — open an issue or PR describing what you'd like to change.*
