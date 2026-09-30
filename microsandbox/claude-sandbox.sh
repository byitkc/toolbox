#!/usr/bin/env bash
# Open an interactive bash shell inside a microsandbox VM (run `claude` from
# there), with herdr agent detection enabled.
#
# Usage:
#   ./claude-sandbox.sh                          # per-directory sandbox with $PWD at /workspace/<name>
#   ./claude-sandbox.sh -n other                 # shell in the "other" sandbox (as-is)
#   ./claude-sandbox.sh -- -c 'claude --resume'  # extra args are passed to the command
#   ./claude-sandbox.sh --cmd claude -- --resume # run claude instead of bash
#
# Options:
#   -n, --name NAME   Sandbox to exec into (default: claude-<dir>-<hash> for the cwd,
#                     or $CLAUDE_SANDBOX_NAME). Explicit names are never auto-created.
#   --cmd COMMAND     Command to run instead of bash (a single executable; put its
#                     arguments after --)
#   -h, --help        Show this help
#
# msb exec cannot mount anything, so on first use in a directory this forks the
# "claude" sandbox (see fork-claude-sandbox.sh) with that directory mounted.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="${CLAUDE_SANDBOX_NAME:-}"
CMD="bash"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--name)
      if [ -z "$2" ]; then
        echo "error: $1 requires a value" >&2
        exit 2
      fi
      NAME="$2"
      shift 2
      ;;
    --name=*)
      NAME="${1#--name=}"
      shift
      ;;
    --cmd)
      if [ -z "$2" ]; then
        echo "error: $1 requires a value" >&2
        exit 2
      fi
      CMD="$2"
      shift 2
      ;;
    --cmd=*)
      CMD="${1#--cmd=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$NAME" ]; then
  HASH="$(printf %s "$PWD" | cksum | cut -d' ' -f1)"
  BASE="$(basename "$PWD" | tr -c 'A-Za-z0-9\n' '-' | cut -c1-30)"
  NAME="claude-$BASE-$HASH"
  if ! msb inspect "$NAME" >/dev/null 2>&1; then
    echo "==> No sandbox for $PWD; creating '$NAME'"
    "$SCRIPT_DIR/fork-claude-sandbox.sh" --dir "$PWD" -n "$NAME" || exit 1
  fi
fi

# Each fork mounts its directory at /workspace/<name> (unique per sandbox, so
# Claude's per-directory state isn't shared). Fall back to /workspace for
# sandboxes forked before that change.
HERDR_AGENT=claude exec msb exec -t "$NAME" -- sh -c \
  'cd "/workspace/$0" 2>/dev/null || cd /workspace; exec "$@"' "$NAME" "$CMD" "$@"
