#!/usr/bin/env bash
# Start an interactive Claude Code session inside a microsandbox VM, with herdr
# agent detection enabled.
#
# Usage:
#   ./claude-sandbox.sh                          # session in the "claude" sandbox
#   ./claude-sandbox.sh -n other                 # session in the "other" sandbox
#   ./claude-sandbox.sh -- --resume              # extra args are passed to claude
#
# Options:
#   -n, --name NAME   Sandbox to exec into (default: claude, or $CLAUDE_SANDBOX_NAME)
#   -h, --help        Show this help

NAME="${CLAUDE_SANDBOX_NAME:-claude}"

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

HERDR_AGENT=claude exec msb exec -t "$NAME" -- claude "$@"
