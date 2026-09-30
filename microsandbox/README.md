# Claude Code Sandbox Scripts

Helper scripts for running [Claude Code](https://claude.com/claude-code) inside [microsandbox](https://github.com/microsandbox/microsandbox) VMs (the `msb` CLI). Each project directory gets its own isolated VM, forked from a shared base image, so Claude runs with access only to the directory you mount.

## Files

| File | Purpose |
| --- | --- |
| `setup-claude-sandbox.sh` | One-time creation of the base `claude` VM with Claude Code installed |
| `fork-claude-sandbox.sh` | Clone the base VM (via disk snapshot) into a new named sandbox, optionally installing extra tools |
| `claude-sandbox.sh` | Day-to-day launcher: starts an interactive Claude session, creating a per-directory sandbox if needed |
| `claude-mounts.yaml` | Mount definitions used by the setup script for the base VM |

## Typical workflow

```
./setup-claude-sandbox.sh      # once: build the base "claude" VM
cd ~/some/project
/path/to/claude-sandbox.sh     # every time: run Claude against this directory
```

## Scripts

### `setup-claude-sandbox.sh`

Creates the long-lived base sandbox named `claude` (`node:24-bookworm-slim`, 2 CPUs, 4G RAM, 8G root disk, workdir `/workspace`), then installs inside it:

- apt packages: `ca-certificates`, `git`, `ripgrep`, `gh`
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

Snapshots an existing sandbox (default `claude`) and restores the snapshot into a new named sandbox. The source is left unchanged. Host bind mounts aren't part of a snapshot, so the script re-supplies them: the work dir at `/workspace`, `~/.agents` read-only at `/root/.agents`, the `claude-home` volume at `/root/.claude`, and `~/.claude.json` if present.

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
| `--dir DIR` | Host directory mounted at `/workspace` (default: the script's own directory) |
| `-h`, `--help` | Show help |

Caveat (from the script's own note): whether the `claude-home` volume, `CLAUDE_CONFIG_DIR`, and secrets carry over on restore is undocumented, so verify after the first run.

### `claude-sandbox.sh`

Launches an interactive `claude` session in a sandbox via `msb exec -t`, with `HERDR_AGENT=claude` set so herdr can detect the agent.

```
./claude-sandbox.sh                # sandbox for $PWD, mounted at /workspace
./claude-sandbox.sh -n other       # use the existing "other" sandbox as-is
./claude-sandbox.sh -- --resume    # pass extra args through to claude
```

- With no `-n` (and no `$CLAUDE_SANDBOX_NAME`), the sandbox is named `claude-<dirname>-<cksum of $PWD>`. If it doesn't exist, the script calls `fork-claude-sandbox.sh --dir "$PWD"` to create it. `msb exec` can't mount anything, which is why the fork step is needed.
- Explicitly named sandboxes are never auto-created.
- Arguments after `--` go to `claude`.

## Requirements

- The `msb` (microsandbox) CLI
- Host `~/.agents` directory (mounted read-only into the VM)
- Optionally `~/.gitconfig` and `~/.claude.json` on the host
