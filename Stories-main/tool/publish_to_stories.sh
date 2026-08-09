#!/usr/bin/env bash
# Push standalone_audiobook_app/ from PlayTorrioV2 to https://github.com/killamfkr/Stories
set -euo pipefail

STORIES_REPO="${STORIES_REPO:-https://github.com/killamfkr/Stories.git}"
BRANCH="${STORIES_BRANCH:-stories-publish-main}"
PLAYTORRIO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$PLAYTORRIO_ROOT"

if [[ ! -d standalone_audiobook_app ]]; then
  echo "Run from PlayTorrioV2 (standalone_audiobook_app/ not found under $PLAYTORRIO_ROOT)"
  exit 1
fi

echo "Splitting standalone_audiobook_app/ → branch $BRANCH"
git subtree split --prefix=standalone_audiobook_app -b "$BRANCH"

echo "Pushing to $STORIES_REPO (main)"
git push "$STORIES_REPO" "$BRANCH:main"

echo "Done: https://github.com/killamfkr/Stories"
