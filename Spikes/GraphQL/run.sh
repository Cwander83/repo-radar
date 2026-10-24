#!/usr/bin/env bash
# Run the Repo Radar query with the gh CLI's token.
# Usage: Spikes/GraphQL/run.sh owner/repo [owner/repo ...] > out.json
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 owner/repo [owner/repo ...]" >&2
  exit 1
fi

dir="$(cd "$(dirname "$0")" && pwd)"
search=""
for repo in "$@"; do
  search="$search repo:$repo"
done

gh api graphql -F query=@"$dir/RepoRadar.graphql" -f search="${search# }"
