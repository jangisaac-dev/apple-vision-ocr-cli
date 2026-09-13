#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# The installer copies wrappers without the .sh suffix; the repo copy keeps it.
TARGET="$SCRIPT_DIR/vocr-finder-action"
[[ -x "$TARGET" ]] || TARGET="$SCRIPT_DIR/vocr-finder-action.sh"
exec "$TARGET" "$@"
