#!/usr/bin/env bash
#
# push_to_github.sh
#
# One-shot helper to turn this project folder into a git repo and push it
# to GitHub. Safe to re-run. Designed for Git Bash on Windows.
#
# Usage:
#   1. Create an EMPTY repo on github.com (no README, no .gitignore, no license)
#   2. Copy its URL (https://github.com/<you>/aws-serverless-etl-pipeline.git)
#   3. Put this script in the project root, then in Git Bash:
#        cd /c/Users/ujjwa/Downloads/aws-serverless-etl-pipeline
#        bash push_to_github.sh
#

set -e  # stop on first error

echo "=================================================="
echo " Push AWS ETL project to GitHub"
echo "=================================================="
echo

# --- Sanity check: are we in the right folder? ---
if [ ! -f "README.md" ] || [ ! -d "terraform" ]; then
  echo "ERROR: This doesn't look like the project folder."
  echo "Expected to find README.md and a terraform/ folder here."
  echo "cd into the aws-serverless-etl-pipeline folder first, then re-run."
  exit 1
fi

# --- Safety check: make sure no AWS secrets are about to be committed ---
echo "Scanning for anything that looks like an AWS access key..."
if grep -rExq 'AKIA[0-9A-Z]{16}' . --include='*.tf' --include='*.py' --include='*.json' --include='*.md' 2>/dev/null; then
  echo
  echo "WARNING: Found something matching an AWS access key pattern (AKIA...)."
  echo "Aborting so you can remove it first. Nothing was committed."
  exit 1
fi
echo "  ...clean, no keys found."
echo

# --- Ask for the repo URL ---
read -rp "Paste your empty GitHub repo URL (ending in .git): " REPO_URL
if [ -z "$REPO_URL" ]; then
  echo "No URL entered. Exiting."
  exit 1
fi

# --- Init repo if not already one ---
if [ ! -d ".git" ]; then
  echo "Initializing new git repository..."
  git init
  git branch -M main
else
  echo "Git repo already exists here - reusing it."
fi

# --- Stage everything (respecting .gitignore) ---
echo "Staging files..."
git add .

# --- Show what will be committed ---
echo
echo "About to commit these files:"
git status --short
echo

read -rp "Commit and push these? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo "Stopped. Nothing was pushed. (Files are staged; you can commit manually.)"
  exit 0
fi

# --- Commit ---
git commit -m "Initial commit - serverless ETL pipeline (S3, Lambda, Glue, Step Functions, Athena) with Terraform and evidence"

# --- Wire up the remote (handle the case where it already exists) ---
if git remote | grep -q "^origin$"; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

# --- Push ---
echo "Pushing to GitHub..."
git push -u origin main

echo
echo "=================================================="
echo " Done. Your repo is live at:"
echo " ${REPO_URL%.git}"
echo "=================================================="
