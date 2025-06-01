#!/bin/bash

# Use the provided date for the backup directory
USER=$1
BACKUP_DATE="yyyy-mm-dd"
BACKUP_DIR="github_backup_${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

# Get all repositories for appatalks
echo "Fetching repository list for appatalks..."
gh repo list $1 --limit 1000 --json nameWithOwner -q '.[].nameWithOwner' | while read repo; do
  echo "====================================="
  echo "Cloning $repo (full repository with all branches)"
  
  # Extract just the repo name from the full name
  repo_name=$(basename "$repo")
  
  # Clone the repository with all branches
  gh repo clone "$repo" "$repo_name"
  
  # Enter the repo directory and fetch all branches
  cd "$repo_name"
  git fetch --all
  
  # List remote branches and create local branches to track them
  git branch -r | grep -v '\->' | grep -v 'origin/HEAD' | while read remote; do
    branch_name="${remote#origin/}"
    echo "Setting up local branch for $branch_name"
    git branch --track "$branch_name" "$remote" 2>/dev/null || true
  done
  
  # Return to backup directory for next repository
  cd ..
  echo "Completed backup of $repo"
  echo "====================================="
done

echo "Backup completed in $(pwd)"
echo "Backed up on: 2025-06-01 18:18:48 UTC"
