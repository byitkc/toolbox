#!/usr/bin/env bash
# Create (or, with --rebuild, recreate) the long-lived "claude" microsandbox VM,
# then install Claude Code inside it.
#
# Usage:
#   ./setup-claude-sandbox.sh            # first-time create + setup
#   ./setup-claude-sandbox.sh --rebuild  # intentionally destroy and recreate the VM
#
# Requires GITHUB_TOKEN and ANTHROPIC_API_KEY set in this shell's environment
# (msb resolves --secret 'VAR@host' by reading VAR from the host env at create time).
#
# Afterwards, start a session with:
#   msb exec -t claude -- claude

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Referenced as ${AGENTS_DIR} in claude-mounts.yaml.
export AGENTS_DIR="$(readlink -f "$HOME/.agents")"

CREATE_ARGS=(
  --name claude
  --cpus 2 --memory 4G --root-disk 8G
  # Drive mappings live in claude-mounts.yaml next to this script.
  --fs-conf "$SCRIPT_DIR/claude-mounts.yaml"
  --workdir /workspace
  # --secret 'ANTHROPIC_API_KEY@api.anthropic.com'
  # --secret 'GITHUB_TOKEN@github.com,api.github.com'
  -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
  # Claude Code's login state (oauthAccount, etc.) normally lives in
  # ~/.claude.json, which is OUTSIDE the persisted claude-home volume and
  # gets wiped on every rebuild. Pointing CLAUDE_CONFIG_DIR at the mounted
  # volume moves that file to /root/.claude/.claude.json so login survives.
  -e CLAUDE_CONFIG_DIR=/root/.claude
)

if [ "$1" = "--rebuild" ]; then
  CREATE_ARGS=(--replace "${CREATE_ARGS[@]}")
fi

if [ -f "$HOME/.gitconfig" ]; then
  CREATE_ARGS+=(--mount-file "$HOME/.gitconfig:/root/.gitconfig:ro")
fi

msb create "${CREATE_ARGS[@]}" node:24-bookworm-slim

msb exec claude -- sh -lc '
  apt-get update &&
  apt-get install -y --no-install-recommends ca-certificates git ripgrep gh &&
  npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code &&
  mkdir -p /root/.claude &&
  ln -sfn /root/.agents/skills /root/.claude/skills &&
  printf "@/root/.agents/AGENTS.md\n" > /root/.claude/CLAUDE.md
'

echo "Setup complete. Start a session with: msb exec -t claude -- claude"
