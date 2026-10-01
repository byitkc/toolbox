#!/usr/bin/env bash
# Fork an existing microsandbox VM into a new named sandbox, then install
# additional tools in the fork. Uses a disk snapshot of the source, so the
# source sandbox is left unchanged.
#
# Usage:
#   ./fork-claude-sandbox.sh -n research --apt "python3 jq"
#   ./fork-claude-sandbox.sh -n research --script ./extra-tools.sh
#   ./fork-claude-sandbox.sh --from claude -n research --apt "jq" --script ./more.sh
#
# Options:
#   -n, --name NAME     Name of the new sandbox (required)
#   --from NAME         Source sandbox to fork (default: claude)
#   --apt "PKGS"        Space-separated apt packages to install in the fork
#   --script FILE       Shell script to run inside the fork (after --apt)
#   --dir DIR           Host directory mounted at /workspace/NAME (default: this script's dir)
#   -h, --help          Show this help
#
# Afterwards, start a session with:
#   ./claude-sandbox.sh -n NAME
#
# NOTE: host bind mounts are not part of a snapshot, so they are re-supplied
# below with -v. Whether the claude-home named volume, CLAUDE_CONFIG_DIR, and
# secrets carry over on restore is not documented; verify after the first run.
# Likewise verify that the nested claude-projects-NAME volume mounts over
# /root/.claude/projects.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="claude"
NAME=""
APT_PKGS=""
EXTRA_SCRIPT=""
WORK_DIR="$SCRIPT_DIR"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

need_value() {
  if [ -z "$2" ]; then
    echo "error: $1 requires a value" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--name)   need_value "$1" "$2"; NAME="$2"; shift 2 ;;
    --name=*)    NAME="${1#--name=}"; shift ;;
    --from)      need_value "$1" "$2"; SOURCE="$2"; shift 2 ;;
    --from=*)    SOURCE="${1#--from=}"; shift ;;
    --apt)       need_value "$1" "$2"; APT_PKGS="$2"; shift 2 ;;
    --apt=*)     APT_PKGS="${1#--apt=}"; shift ;;
    --script)    need_value "$1" "$2"; EXTRA_SCRIPT="$2"; shift 2 ;;
    --script=*)  EXTRA_SCRIPT="${1#--script=}"; shift ;;
    --dir)       need_value "$1" "$2"; WORK_DIR="$(cd "$2" && pwd)" || exit 2; shift 2 ;;
    --dir=*)     WORK_DIR="$(cd "${1#--dir=}" && pwd)" || exit 2; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$NAME" ]; then
  echo "error: --name is required" >&2
  usage >&2
  exit 2
fi

if [ -n "$EXTRA_SCRIPT" ] && [ ! -f "$EXTRA_SCRIPT" ]; then
  echo "error: script not found: $EXTRA_SCRIPT" >&2
  exit 2
fi

SNAP="fork-$NAME"
AGENTS_DIR="$(readlink -f "$HOME/.agents")"

# Claude keys sessions and ~/.claude.json project state by working directory, so
# every sandbox using /workspace would share history. Mount each sandbox's dir at
# a unique path, and give it its own volume for session transcripts.
WORK_MOUNT="/workspace/$NAME"
PROJECTS_VOLUME="claude-projects-$NAME"

echo "==> Snapshotting '$SOURCE' as $SOURCE:$SNAP"
msb snap create "$SNAP" --sandbox "$SOURCE" || exit 1

# Host bind mounts must be re-supplied on restore. The claude-home mount is
# unverified (see NOTE above).
RESTORE_ARGS=(
  --name "$NAME"
  -c "2"
  -m "2G"
  -v "$WORK_DIR:$WORK_MOUNT"
  -v "$AGENTS_DIR:/root/.agents:ro"
  -v "claude-home:/root/.claude"
  # Nested over claude-home: credentials, CLAUDE.md and skills stay shared, but
  # session transcripts (projects/) are per sandbox.
  -v "$PROJECTS_VOLUME:/root/.claude/projects"
)

if [ -f "$HOME/.claude.json" ]; then
  RESTORE_ARGS+=(-v "$HOME/.claude.json:/root/.claude.json")
fi

echo "==> Restoring $SOURCE:$SNAP into '$NAME'"
msb snap restore "$SOURCE:$SNAP" "${RESTORE_ARGS[@]}" || exit 1

# Copy passphrase-protected private keys from the host's ~/.ssh into the VM.
# Unencrypted keys are never copied: `ssh-keygen -y -P ''` succeeds only when a
# key has no passphrase. Content is passed as base64 in the command string
# because msb exec stdin forwarding is unverified.
SSH_COPIED=0
if [ -d "$HOME/.ssh" ] && command -v ssh-keygen >/dev/null 2>&1; then
  for key in "$HOME"/.ssh/*; do
    [ -f "$key" ] || continue
    grep -q 'PRIVATE KEY' "$key" 2>/dev/null || continue
    if ssh-keygen -y -P '' -f "$key" >/dev/null 2>&1; then
      echo "==> Skipping unencrypted SSH key: $key"
      continue
    fi
    b64="$(base64 < "$key" | tr -d '\n')"
    msb exec "$NAME" -- sh -c '
      mkdir -p /root/.ssh && chmod 700 /root/.ssh &&
      printf %s "$1" | base64 -d > "/root/.ssh/$0" &&
      chmod 600 "/root/.ssh/$0"
    ' "$(basename "$key")" "$b64" || exit 1
    echo "==> Copied encrypted SSH key: $(basename "$key")"
    SSH_COPIED=$((SSH_COPIED + 1))
  done
fi

if [ -n "$APT_PKGS" ]; then
  echo "==> Installing apt packages: $APT_PKGS"
  msb exec "$NAME" -- sh -lc \
    "apt-get update && apt-get install -y --no-install-recommends $APT_PKGS" || exit 1
fi

if [ -n "$EXTRA_SCRIPT" ]; then
  echo "==> Running $EXTRA_SCRIPT in '$NAME'"
  msb exec "$NAME" -- sh -lc "$(cat "$EXTRA_SCRIPT")" || exit 1
fi

echo "Workspace mounted at $WORK_MOUNT; sessions stored in volume '$PROJECTS_VOLUME'"
echo "Fork complete. Start a session with: ./claude-sandbox.sh -n $NAME"
