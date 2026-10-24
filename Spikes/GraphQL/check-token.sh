#!/usr/bin/env bash
# Run the Repo Radar query with a token you paste (e.g. a fine-grained PAT) and
# report what it can see. The token is read silently and never printed or saved.
# Usage: Spikes/GraphQL/check-token.sh owner/repo [owner/repo ...]
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 owner/repo [owner/repo ...]" >&2
  exit 1
fi

dir="$(cd "$(dirname "$0")" && pwd)"
printf 'Paste token (input hidden): ' >&2
read -rs token
echo >&2

GH_TOKEN="$token" "$dir/run.sh" "$@" | jq '{
  viewer: .data.viewer.login,
  cost: .data.rateLimit.cost,
  errors: [.errors[]?.message],
  repos: [.data.search.nodes[] | {
    repo: .nameWithOwner,
    defaultBranch: .defaultBranchRef.name,
    rollup: .defaultBranchRef.target.statusCheckRollup.state,
    checkRuns: ([.defaultBranchRef.target.statusCheckRollup.contexts.nodes[]? | select(.__typename == "CheckRun")] | length),
    statuses: ([.defaultBranchRef.target.statusCheckRollup.contexts.nodes[]? | select(.__typename == "StatusContext")] | length),
    openPRs: .pullRequests.totalCount,
    branches: .refs.totalCount
  }]
}'
unset token
