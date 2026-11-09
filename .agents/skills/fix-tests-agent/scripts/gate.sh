#!/bin/sh
# Exit 0 when an open GitHub issue has label ci-tier2 (print numbers).
# Exit 1 when none — agent-orc skips the scheduled tick.
set -eu

json=$(gh issue list --label ci-tier2 --state open --limit 10 --json number)

nums=$(printf '%s\n' "$json" | jq -r '.[].number')

if [ -n "$nums" ]; then
  printf '%s\n' "$nums"
  exit 0
fi

exit 1
