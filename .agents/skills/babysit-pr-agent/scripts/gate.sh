#!/bin/sh
# Exit 0 when babysit should run: a same-repo open PR is conflicted, behind its
# base, or has a failing check; or more than 3 same-repo open PRs have
# queued/in-progress checks (soft Actions queue). Exit 1 when neither.
# When eligible fix targets exist, print their numbers (one per line).
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

active=$(
  printf '%s\n' "$json" | jq -r '
    [
      .[]
      | select(.isCrossRepository == false)
      | select(any(.statusCheckRollup[]?;
          .status == "QUEUED"
          or .status == "IN_PROGRESS"
          or .status == "PENDING"
          or .status == "WAITING"
          or .status == "REQUESTED"
          or .state == "PENDING"
          or .state == "EXPECTED"
        ))
      | .number
    ] | length
  '
)

if [ -n "$nums" ]; then
  printf '%s\n' "$nums"
  exit 0
fi

if [ "$active" -gt 3 ]; then
  exit 0
fi

exit 1
