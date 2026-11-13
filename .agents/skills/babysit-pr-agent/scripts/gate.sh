#!/bin/sh
# Exit 0 when babysit should run: a same-repo open PR is conflicted, behind its
# base, or has a failing check. Exit 1 when none. When eligible fix targets
# exist, print their numbers (one per line).
# agent-orc treats only the exit code as the gate.
set -eu

json=$(
  gh pr list --state open --limit 50 \
    --json number,isCrossRepository,mergeable,mergeStateStatus,statusCheckRollup
)

nums=$(
  printf '%s\n' "$json" | jq -r '
    map(select(.isCrossRepository == false) | select(
      .mergeable == "CONFLICTING"
      or .mergeStateStatus == "DIRTY"
      or .mergeStateStatus == "BEHIND"
      or any(.statusCheckRollup[]?;
        .conclusion == "FAILURE"
        or .conclusion == "CANCELLED"
        or .conclusion == "TIMED_OUT"
        or .conclusion == "STARTUP_FAILURE"
        or .state == "FAILURE"
        or .state == "ERROR"
      )
    )) | .[].number
  '
)

if [ -n "$nums" ]; then
  printf '%s\n' "$nums"
  exit 0
fi

exit 1
