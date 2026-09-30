# Claude Code Sandbox Scripts

Helper scripts for running [Claude Code](https://claude.com/claude-code) inside [microsandbox](https://github.com/microsandbox/microsandbox) VMs (the `msb` CLI). Each project directory gets its own isolated VM, forked from a shared base image, so Claude runs with access only to the directory you mount.

## Files

| File | Purpose |
| --- | --- |
| `setup-claude-sandbox.sh` | One-time creation of the base `claude` VM with Claude Code installed |
| `fork-claude-sandbox.sh` | Clone the base VM (via disk snapshot) into a new named sandbox, optionally installing extra tools |
| `claude-sandbox.sh` | Day-to-day launcher: opens a bash shell in the sandbox (run `claude` from there), creating a per-directory sandbox if needed |
| `claude-mounts.yaml` | Mount definitions used by the setup script for the base VM |

## Typical workflow

```
./setup-claude-sandbox.sh      # once: build the base "claude" VM
cd ~/some/project
/path/to/claude-sandbox.sh     # every time: open a shell in this directory's sandbox, then run `claude`
```

## Scripts

### `setup-claude-sandbox.sh`

Creates the long-lived base sandbox named `claude` (`node:24-bookworm-slim`, 2 CPUs, 4G RAM, 8G root disk, workdir `/workspace`), then installs inside it:

- apt packages: `ca-certificates`, `git`, `openssh-client`, `ripgrep`, `gh`
- `@anthropic-ai/claude-code` (global npm install)
- a `/root/.claude/skills` symlink to `/root/.agents/skills`
- `/root/.claude/CLAUDE.md` containing `@/root/.agents/AGENTS.md`, so your global agent instructions apply in the sandbox

Also mounts the host's `~/.gitconfig` (read-only) and `~/.claude.json` (read-write, so login state survives rebuilds) when they exist. Sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.

```
./setup-claude-sandbox.sh            # first-time create + setup
./setup-claude-sandbox.sh --rebuild  # destroy and recreate the VM
```

Notes:
- The `--secret` lines for `ANTHROPIC_API_KEY` and `GITHUB_TOKEN` are currently commented out. The header says both must be set in the host environment; enable those lines if you want the secrets injected.
- Changes to `claude-mounts.yaml` only take effect on `--rebuild`. The `claude-home` named volume persists across rebuilds.
- Uses `set -e`.

### `fork-claude-sandbox.sh`

Snapshots an existing sandbox (default `claude`) and restores the snapshot into a new named sandbox. The source is left unchanged. Host bind mounts aren't part of a snapshot, so the script re-supplies them: the work dir at `/workspace/<name>`, `~/.agents` read-only at `/root/.agents`, the shared `claude-home` volume at `/root/.claude`, a per-sandbox `claude-projects-<name>` volume at `/root/.claude/projects`, and `~/.claude.json` if present.

SSH keys: when the new sandbox is created, every passphrase-protected private key in the host's `~/.ssh` is copied into `/root/.ssh` in the VM (mode 600). Unencrypted keys, public keys and non-key files are skipped, so decrypt/load them inside the VM as needed (`ssh-add`, `ssh-keygen -p`). Keys are copied via `msb exec` and never land in this directory.

Session isolation: Claude keys sessions and `~/.claude.json` project state by working directory. Each sandbox therefore gets a unique work path (`/workspace/<name>`) and its own `projects/` volume, so chat history and subagent transcripts aren't shared between sandboxes. Credentials, `CLAUDE.md` and skills stay shared via `claude-home`. `history.jsonl` and `todos/` are still shared.

```
./fork-claude-sandbox.sh -n research --apt "python3 jq"
./fork-claude-sandbox.sh -n research --script ./extra-tools.sh
./fork-claude-sandbox.sh --from claude -n research --apt "jq" --script ./more.sh
```

| Option | Description |
| --- | --- |
| `-n`, `--name NAME` | Name of the new sandbox (required) |
| `--from NAME` | Source sandbox to fork (default `claude`) |
| `--apt "PKGS"` | Space-separated apt packages to install in the fork |
| `--script FILE` | Shell script to run inside the fork, after `--apt` |
| `--dir DIR` | Host directory mounted at `/workspace/<name>` (default: the script's own directory) |
| `-h`, `--help` | Show help |

Caveat (from the script's own note): whether the `claude-home` volume, `CLAUDE_CONFIG_DIR`, and secrets carry over on restore is undocumented, so verify after the first run. Also verify that the nested `claude-projects-<name>` volume mounts over `/root/.claude/projects`.

### `claude-sandbox.sh`

Opens an interactive `bash` shell in a sandbox via `msb exec -t`, in the sandbox's work directory. Run `claude` from that shell. `HERDR_AGENT=claude` is still set on the `msb` process so herdr can detect the agent.

```
./claude-sandbox.sh                # sandbox for $PWD, mounted at /workspace/<sandbox-name>
./claude-sandbox.sh -n other       # use the existing "other" sandbox as-is
./claude-sandbox.sh -- -c 'claude --resume'   # pass extra args through to the command
./claude-sandbox.sh --cmd claude -- --resume  # run claude instead of bash
```

- With no `-n` (and no `$CLAUDE_SANDBOX_NAME`), the sandbox is named `claude-<dirname>-<cksum of $PWD>`. If it doesn't exist, the script calls `fork-claude-sandbox.sh --dir "$PWD"` to create it. `msb exec` can't mount anything, which is why the fork step is needed.
- Explicitly named sandboxes are never auto-created.
- The shell starts in `/workspace/<sandbox-name>`, falling back to `/workspace` for sandboxes forked before per-sandbox paths existed (those keep sharing the old `/workspace` state).
- `--cmd COMMAND` replaces `bash` with another command (a single executable, no embedded arguments). Arguments after `--` go to whichever command runs.

## Requirements

- The `msb` (microsandbox) CLI
- Host `~/.agents` directory (mounted read-only into the VM)
- Optionally `~/.gitconfig` and `~/.claude.json` on the host
