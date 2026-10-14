#!/usr/bin/env bash
# Publish this folder as a new GitHub repository.
# Usage:  ./push_to_github.sh <github-username> [repo-name] [public|private]
set -euo pipefail

GH_USER="${1:?Usage: ./push_to_github.sh <github-username> [repo-name] [public|private]}"
REPO="${2:-prestige-city-credit-risk-sas}"
VIS="${3:-public}"

cd "$(dirname "$0")"

if [ ! -d .git ]; then
  git init
  git branch -M main
fi

git add .
git commit -m "Prestige City Bengaluru credit risk lifecycle in SAS" || echo "Nothing new to commit."

if command -v gh >/dev/null 2>&1; then
  # GitHub CLI: creates the repo, sets origin and pushes in one go
  gh repo create "$GH_USER/$REPO" "--$VIS" --source=. --remote=origin --push
else
  echo "GitHub CLI (gh) not found."
  echo "1) Create an EMPTY repo named '$REPO' at https://github.com/new (no README, no .gitignore)"
  echo "2) Press Enter to push"
  read -r _
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$GH_USER/$REPO.git"
  git push -u origin main
fi

echo "Done: https://github.com/$GH_USER/$REPO"
