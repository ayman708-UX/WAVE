#!/usr/bin/env bash
# Prepare standalone_audiobook_app as the root of a new git repository.
# Usage: bash tool/init_standalone_repo.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d .git ]]; then
  echo "Already a git repository: $ROOT"
  exit 0
fi

git init -b main
git add .
git status

cat <<'EOF'

Next steps:
  1. Create an empty repo on GitHub (e.g. YOUR_USER/stories)
  2. git commit -m "Initial commit: Stories audiobook app"
  3. git remote add origin https://github.com/YOUR_USER/stories.git
  4. git push -u origin main

CI: .github/workflows/build_apk.yml builds the APK on push.
EOF
