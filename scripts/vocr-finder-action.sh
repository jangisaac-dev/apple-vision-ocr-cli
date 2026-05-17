#!/bin/zsh
set -euo pipefail

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

LOG="$HOME/Library/Logs/vocr-quick-action.log"
mkdir -p "$(dirname "$LOG")"
exec 1>>"$LOG"
exec 2>>"$LOG"

echo "================================================================="
echo "[$(date)] Launching VOCR"
echo "Arguments: $@"

APP="${VOCR_APP:-$HOME/Applications/VOCR.app}"
if [[ ! -d "$APP" ]]; then
  echo "VOCR.app not found: $APP"
  osascript -e 'display notification "VOCR.app을 찾지 못했습니다." with title "Apple Vision OCR"' >/dev/null 2>&1 || true
  exit 127
fi

if [[ "$#" -eq 0 ]]; then
  echo "No files received from Finder"
fi

open -n "$APP" --args "$@"
