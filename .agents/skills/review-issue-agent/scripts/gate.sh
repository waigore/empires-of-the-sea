#!/bin/sh
# Exit 0 when an open GitHub issue has label resolved (print numbers).
# Exit 1 when none — agent-orc skips the continuous tick.
set -eu

json=$(gh issue list --label resolved --state open --limit 50 --json number)

nums=$(printf '%s\n' "$json" | jq -r '.[].number')

if [ -n "$nums" ]; then
  printf '%s\n' "$nums"
  exit 0
fi

exit 1
