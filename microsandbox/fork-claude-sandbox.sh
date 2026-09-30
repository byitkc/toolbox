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
#   -h, --help          Show this help
#
# Afterwards, start a session with:
#   ./claude-sandbox.sh -n NAME
#
# NOTE: host bind mounts are not part of a snapshot, so they are re-supplied
# below with -v. Whether the claude-home named volume, CLAUDE_CONFIG_DIR, and
# secrets carry over on restore is not documented; verify after the first run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="claude"
NAME=""
APT_PKGS=""
EXTRA_SCRIPT=""

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

echo "==> Snapshotting '$SOURCE' as $SOURCE:$SNAP"
msb snap create "$SNAP" --sandbox "$SOURCE" || exit 1

# Host bind mounts must be re-supplied on restore. The claude-home mount is
# unverified (see NOTE above).
RESTORE_ARGS=(
  --name "$NAME"
  -v "$SCRIPT_DIR:/workspace"
  -v "$AGENTS_DIR:/root/.agents:ro"
  -v "claude-home:/root/.claude"
)

echo "==> Restoring $SOURCE:$SNAP into '$NAME'"
msb snap restore "$SOURCE:$SNAP" "${RESTORE_ARGS[@]}" || exit 1

if [ -n "$APT_PKGS" ]; then
  echo "==> Installing apt packages: $APT_PKGS"
  msb exec "$NAME" -- sh -lc \
    "apt-get update && apt-get install -y --no-install-recommends $APT_PKGS" || exit 1
fi

if [ -n "$EXTRA_SCRIPT" ]; then
  echo "==> Running $EXTRA_SCRIPT in '$NAME'"
  msb exec "$NAME" -- sh -lc "$(cat "$EXTRA_SCRIPT")" || exit 1
fi

echo "Fork complete. Start a session with: ./claude-sandbox.sh -n $NAME"
