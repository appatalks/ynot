#!/usr/bin/env bash
#
# fill repositories with data like digital tides moving sand
#
####
set -euo pipefail

# modules/create-blob-data.sh
# Loads config from config.env and adds various sized files and media files to existing repositories

# Check for noninteractive mode
NONINTERACTIVE=false
if [[ "${1:-}" == "--noninteractive" ]]; then
  NONINTERACTIVE=true
  echo "Running in noninteractive mode - will not prompt for confirmation"
fi

# Function to handle user prompts in noninteractive mode
prompt_user() {
  local prompt_text="$1"
  local default_answer="${2:-y}"  # Default to 'y' if not specified
  
  if [[ "$NONINTERACTIVE" == "true" ]]; then
    return 0
  else
    read -p "$prompt_text" REPLY
    if [[ -z "$REPLY" ]]; then
      REPLY="$default_answer"
    fi
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      return 0
    else
      return 1
    fi
  fi
}

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TMP=$(mktemp -d)
cd "$TMP" || exit 1

# Load global configuration
source "$ROOT_DIR/config.env"

# Set defaults if environment variables not provided
: "${DATA_BLOBS:=false}"
: "${BLOB_MIN_SIZE:=1}"     # Default min size is 1 MB
: "${BLOB_MAX_SIZE:=10}"    # Default max size is 10 MB
: "${BLOB_REPOS_COUNT:=3}"  # Default number of repositories to add blobs to

# Check if blobs should be added
if [[ "$DATA_BLOBS" != "true" ]]; then
  echo "⚠️ DATA_BLOBS is not set to 'true' in config.env. Skipping blob data creation."
  exit 0
fi

# Determine API endpoint and Git URL prefix
if [[ "$GITHUB_SERVER_URL" == "https://github.com" ]]; then
  API="https://api.github.com"
else
  API="${GITHUB_SERVER_URL%/}/api/v3"
fi
GIT_URL_PREFIX="$GITHUB_SERVER_URL"

# Prepare identifiers
AUTH="Authorization: token ${GITHUB_TOKEN}"

# Check if the organization exists
echo "Checking if organization ${ORG} exists..."
ORG_CHECK=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG}" | jq -r '.login // empty')
if [[ -z "$ORG_CHECK" ]]; then
  echo "❌ Organization ${ORG} does not exist."
  exit 1
fi

# Get repositories in the organization
echo "Retrieving repositories from organization ${ORG}..."
REPO_RESPONSE=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG}/repos?per_page=100")

# Check if we got a valid response (array of repos)
if ! echo "$REPO_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
  echo "❌ Failed to retrieve repositories from organization ${ORG}."
  echo "$REPO_RESPONSE" | jq '.'
  exit 1
fi

# Get repository names
REPO_NAMES=($(echo "$REPO_RESPONSE" | jq -r '.[].name'))
REPO_COUNT=${#REPO_NAMES[@]}

if [[ $REPO_COUNT -eq 0 ]]; then
  echo "❌ No repositories found in organization ${ORG}."
  exit 1
fi

echo "Found ${REPO_COUNT} repositories in organization ${ORG}."

# Define additional repositories to include
ADDITIONAL_REPOS=("")
# Add your hardcoded repos here if needed
# ADDITIONAL_REPOS=("your-repo-1" "your-repo-2")

# Combine all repositories
ALL_REPOS=("${REPO_NAMES[@]}" "${ADDITIONAL_REPOS[@]}")
TOTAL_REPOS=${#ALL_REPOS[@]}

# Determine how many repos to add blobs to (use min to avoid exceeding available repos)
REPOS_TO_ADD=$((BLOB_REPOS_COUNT < TOTAL_REPOS ? BLOB_REPOS_COUNT : TOTAL_REPOS))

echo "Will add blob data to ${REPOS_TO_ADD} repositories."

# Function to download files from GitHub
download_github_files() {
  local repo="$1"
  local path="$2"
  local output_dir="$3"
  local count="$4"
  
  mkdir -p "$output_dir"
  
  echo "Attempting to download files from ${repo}/${path}..."
  
  # Get file list from GitHub API with proper headers for better chance of success
  local response
  response=$(curl -s -H "Accept: application/vnd.github.v3+json" -H "User-Agent: ChaosEngine/1.0" "https://api.github.com/repos/${repo}/contents/${path}")
  
  # Check if we got a valid response
  if echo "$response" | jq -e 'type == "array"' > /dev/null; then
    # Response is an array of files
    echo "✅ Received directory listing from GitHub API"
    local download_urls
    download_urls=($(echo "$response" | jq -r '.[] | select(.type == "file") | .download_url'))
    echo "Found ${#download_urls[@]} files in the repository path"
  
  elif echo "$response" | jq -e 'type == "object" and has("download_url")' > /dev/null; then
    # Response is a single file, not a directory
    echo "ℹ️ Path is a single file, not a directory"
    local download_url=$(echo "$response" | jq -r '.download_url')
    download_urls=("$download_url")
    echo "Will download the single file"
  
  elif echo "$response" | jq -e 'type == "object" and has("message")' > /dev/null; then
    # Error response from API
    local error_msg
    error_msg=$(echo "$response" | jq -r '.message')
    echo "⚠️ GitHub API error: $error_msg"
    
    # Check if rate limited
    if [[ "$error_msg" == *"rate limit"* ]]; then
      local reset_time
      reset_time=$(echo "$response" | jq -r '.rate.reset // 0')
      local current_time=$(date +%s)
      local wait_seconds=$((reset_time - current_time))
      
      if [[ $wait_seconds -gt 0 && $wait_seconds -lt 300 ]]; then
        echo "Rate limited. Will retry in $wait_seconds seconds..."
        sleep $wait_seconds
        # Try again
        download_github_files "$repo" "$path" "$output_dir" "$count"
        return $?
      fi
    fi
    
    echo "Falling back to generating local files..."
    local random_file="${output_dir}/random-file-$(date +%s).bin"
    generate_random_file "$random_file" 1
    return 0
  
  else
    # Unexpected response format
    echo "⚠️ Unexpected GitHub API response format"
    echo "Falling back to generating local files..."
    local random_file="${output_dir}/random-file-$(date +%s).bin"
    generate_random_file "$random_file" 1
    return 0
  fi
  
  # If no files were found, generate a placeholder file
  if [[ ${#download_urls[@]} -eq 0 ]]; then
    echo "⚠️ No files found at $path"
    echo "Generating random files instead..."
    local random_file="${output_dir}/random-file-$(date +%s).bin"
    generate_random_file "$random_file" 1
    return 0
  fi
  
  # Shuffle array to randomize selection
  local shuffled_urls=()
  for url in "${download_urls[@]}"; do
    shuffled_urls+=("$url")
  done
  
  # Fisher-Yates shuffle
  local i
  for ((i=${#shuffled_urls[@]}-1; i>0; i--)); do
    local j=$((RANDOM % (i+1)))
    local temp="${shuffled_urls[i]}"
    shuffled_urls[i]="${shuffled_urls[j]}"
    shuffled_urls[j]="$temp"
  done
  
  # Download up to count files
  local download_count=0
  for url in "${shuffled_urls[@]}"; do
    if [[ $download_count -ge $count ]]; then
      break
    fi
    
    local filename=$(basename "$url")
    echo "Downloading $filename..."
    curl -s -L "$url" -o "${output_dir}/${filename}"
    download_count=$((download_count + 1))
  done
  
  echo "Downloaded ${download_count} files to ${output_dir}"
}

# Function to generate a random file of specified size in MB
generate_random_file() {
  local output_file="$1"
  local size_mb="$2"
  
  echo "Generating random file of ${size_mb}MB: ${output_file}"
  dd if=/dev/urandom of="$output_file" bs=1M count="$size_mb" 2>/dev/null || \
    dd if=/dev/urandom of="$output_file" bs=1048576 count="$size_mb" 2>/dev/null
}

# Function to calculate random size between min and max
random_size() {
  local min="$1"
  local max="$2"
  echo $(( min + RANDOM % (max - min + 1) ))
}

# Initialize array to track processed repositories
PROCESSED_REPOS=("")

# Process each repository
for ((i=0; i<REPOS_TO_ADD; i++)); do
  # Select a repository randomly that hasn't been processed yet
  MAX_ATTEMPTS=100
  ATTEMPT=0
  REPO_NAME=""
  
  while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    REPO_INDEX=$((RANDOM % TOTAL_REPOS))
    REPO_NAME="${ALL_REPOS[$REPO_INDEX]}"
    
    # Check if this repo has already been processed
    ALREADY_PROCESSED=false
    for processed in "${PROCESSED_REPOS[@]}"; do
      if [[ "$processed" == "$REPO_NAME" ]]; then
        ALREADY_PROCESSED=true
        break
      fi
    done
    
    if [[ "$ALREADY_PROCESSED" == "false" ]]; then
      # Found a repo we haven't processed yet
      PROCESSED_REPOS+=("$REPO_NAME")
      break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    
    # If we've tried too many times, just use any repo
    if [[ $ATTEMPT -ge $MAX_ATTEMPTS ]]; then
      echo "⚠️ Could not find unique repository after $MAX_ATTEMPTS attempts."
      break
    fi
  done
  
  echo -e "\n🔍 Processing repository: ${ORG}/${REPO_NAME}"
  
  # Create a working directory for this repo
  REPO_DIR="${TMP}/${REPO_NAME}"
  mkdir -p "$REPO_DIR"
  
  # Clone the repository
  echo "Cloning repository..."
  if ! git clone "https://x-access-token:${GITHUB_TOKEN}@${GIT_URL_PREFIX#https://}/${ORG}/${REPO_NAME}.git" "$REPO_DIR"; then
    echo "❌ Failed to clone repository ${ORG}/${REPO_NAME}. Skipping..."
    continue
  fi
  cd "$REPO_DIR" || continue
  
  # Create a new branch
  BRANCH_NAME="blob-data-$(date +%s)"
  
  # Try to determine the default branch
  echo "Determining default branch..."
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
  
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo "Could not determine default branch from git config. Checking common branches..."
    
    # Try common branch names
    for branch in main master develop trunk; do
      if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        DEFAULT_BRANCH="$branch"
        echo "Found branch: $DEFAULT_BRANCH"
        break
      fi
    done
    
    # If still no default branch, list all branches and use the first one
    if [[ -z "$DEFAULT_BRANCH" ]]; then
      echo "Could not find common branch names. Listing all branches..."
      ALL_BRANCHES=($(git branch -r | grep -v HEAD | sed 's/origin\///'))
      if [[ ${#ALL_BRANCHES[@]} -gt 0 ]]; then
        DEFAULT_BRANCH="${ALL_BRANCHES[0]}"
        echo "Using first available branch: $DEFAULT_BRANCH"
      else
        echo "❌ No branches found in the repository. Skipping..."
        cd "$TMP" || exit 1
        continue
      fi
    fi
  fi
  
  echo "Using default branch: $DEFAULT_BRANCH"
  
  # Checkout the default branch
  if ! git checkout "$DEFAULT_BRANCH"; then
    echo "❌ Failed to checkout the default branch ${DEFAULT_BRANCH}. Skipping..."
    cd "$TMP" || exit 1
    continue
  fi
  
  # Create and checkout the new branch
  if ! git checkout -b "$BRANCH_NAME"; then
    echo "❌ Failed to create branch ${BRANCH_NAME}. Skipping..."
    cd "$TMP" || exit 1
    continue
  fi
  
  # Create data directory
  DATA_DIR="${REPO_DIR}/blob-data"
  mkdir -p "$DATA_DIR"
  
  # Calculate total size for this repository (random between min and max)
  REPO_SIZE_MB=$(random_size "$BLOB_MIN_SIZE" "$BLOB_MAX_SIZE")
  echo "Target size for this repository: ${REPO_SIZE_MB}MB"
  
  # Function to download a file from a direct URL
  download_direct_url() {
    local url="$1"
    local output_dir="$2"
    local filename="$3"
    
    mkdir -p "$output_dir"
    echo "Downloading $filename from direct URL..."
    if curl -s -L -o "${output_dir}/${filename}" "$url"; then
      echo "✅ Downloaded ${filename} successfully"
      return 0
    else
      echo "⚠️ Failed to download ${filename}"
      return 1
    fi
  }
  
  # Create media directories
  mkdir -p "${DATA_DIR}/images"
  mkdir -p "${DATA_DIR}/archives"
  
  # Try multiple approaches to get sample files
  echo "Attempting to download sample files..."
  
  # First approach: Try GitHub repositories with known files
  echo "Attempting to download from GitHub repositories..."
  # Try several repositories with images
  download_github_files "appatalks/hoshisato.com" "images" "${DATA_DIR}/images" 3
  download_github_files "appatalks/gochu.se" "images" "${DATA_DIR}/images" 3
  
  # Try to download some archive files if available
  # download_github_files "github/gitignore" "" "${DATA_DIR}/archives" 3
  
  # Second approach: Direct download of some public domain images
  echo "Attempting direct downloads of sample images..."
  # Sample URLs for public domain images
  download_direct_url "https://raw.githubusercontent.com/appatalks/chatgpt-html/main/core/img/screenshot.png" "${DATA_DIR}/images" "sample-image-1.png"
  download_direct_url "https://raw.githubusercontent.com/appatalks/chatgpt-html/main/core/img/background.jpg" "${DATA_DIR}/images" "sample-image-2.jpg"
  download_direct_url "https://raw.githubusercontent.com/appatalks/chatgpt-html/main/core/img/768-026.jpeg" "${DATA_DIR}/images" "sample-image-3.jpeg"

  # Sample URLs for binary/archive files
  download_direct_url "https://raw.githubusercontent.com/github/gitignore/main/Global/Archives.gitignore" "${DATA_DIR}/archives" "archive-gitignore.txt"
  
  # Fallback - Generate files of different types if directories are empty or have too few files
  IMAGE_FILE_COUNT=$(find "${DATA_DIR}/images" -type f | wc -l)
  if [[ $IMAGE_FILE_COUNT -lt 3 ]]; then
    echo "Images directory has fewer than 3 files. Creating additional example files..."
    # Create sample files of different types
    echo "This is an example text file for testing" > "${DATA_DIR}/images/example.txt"
    
    # Create a simple PNG-like binary file
    cat > "${DATA_DIR}/images/example.png" << 'EOF'
PNG

IHDR00000e000000e0080200000107971PLTE{.ř.ř/ř0ś1Ŝ2ŝ4Ş4Ş:Ť:Ť:Ť?ť@Ŧ@ŦAŽAŽA';
EOF
    
    # Create some binary files
    for i in {1..3}; do
      generate_random_file "${DATA_DIR}/images/random-image-${i}.bin" 1
    done
  fi
  
  ARCHIVE_FILE_COUNT=$(find "${DATA_DIR}/archives" -type f | wc -l)
  if [[ $ARCHIVE_FILE_COUNT -lt 3 ]]; then
    echo "Archives directory has fewer than 3 files. Creating additional example files..."
    
    # Create a sample tar.gz-like header
    cat > "${DATA_DIR}/archives/example.tar.gz" << 'EOF'
1F8B0800000000000003EDBD07601C499625262F6DCA7B7F4AF54AD7E074A10880601324D8904010ECC188CDE692EC1D69472329AB2A81CA6556655D661640CCED9DBCF7DE7BEFBDF7DE7BEFBDF7BA3B9D4E27F7DFFF3F5C79F3FF607060606027F
EOF
    
    # Create additional binary files
    for i in {1..3}; do
      generate_random_file "${DATA_DIR}/archives/random-archive-${i}.tar.gz" 1
    done
    
    # Create a sample JSON file that simulates settings
    cat > "${DATA_DIR}/archives/settings.json" << 'EOF'
{
  "name": "test-repo",
  "version": "1.0.0",
  "description": "Test repository for Chaos Engine",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [
    "test",
    "chaos",
    "github"
  ],
  "author": "Chaos Engine",
  "license": "MIT"
}
EOF
  fi
  
  # Generate additional random files to reach the target size
  CURRENT_SIZE=$(du -sm "$DATA_DIR" | cut -f1)
  REMAINING_SIZE=$((REPO_SIZE_MB - CURRENT_SIZE))
  
  if [[ $REMAINING_SIZE -gt 0 ]]; then
    echo "Generating additional random files to reach target size..."
    
    # Generate 1-3 larger files
    NUM_LARGE_FILES=$((1 + RANDOM % 3))
    for ((j=1; j<=NUM_LARGE_FILES; j++)); do
      if [[ $REMAINING_SIZE -le 0 ]]; then
        break
      fi
      
      FILE_SIZE=$((1 + RANDOM % REMAINING_SIZE))
      if [[ $FILE_SIZE -gt $REMAINING_SIZE ]]; then
        FILE_SIZE=$REMAINING_SIZE
      fi
      
      generate_random_file "${DATA_DIR}/large_file_${j}.bin" "$FILE_SIZE"
      REMAINING_SIZE=$((REMAINING_SIZE - FILE_SIZE))
    done
    
    # Generate several smaller files
    NUM_SMALL_FILES=$((5 + RANDOM % 10))
    for ((j=1; j<=NUM_SMALL_FILES; j++)); do
      if [[ $REMAINING_SIZE -le 0 ]]; then
        break
      fi
      
      FILE_SIZE=$((1 + RANDOM % (REMAINING_SIZE < 5 ? REMAINING_SIZE : 5)))
      generate_random_file "${DATA_DIR}/small_file_${j}.bin" "$FILE_SIZE"
      REMAINING_SIZE=$((REMAINING_SIZE - FILE_SIZE))
    done
  fi
  
  # Calculate actual final size
  FINAL_SIZE=$(du -sm "$DATA_DIR" | cut -f1)
  echo "Final blob data size: ${FINAL_SIZE}MB"
  
  # Generate a README file
  cat > "${DATA_DIR}/README.md" << EOF
# Blob Data Files

This directory contains test data files generated on $(date).

Total data size: approximately ${FINAL_SIZE}MB.

These files are used for testing storage, bandwidth, and API functionality.
EOF
  
  # Commit and push changes
  git add "$DATA_DIR" || {
    echo "❌ Failed to add files to git. Skipping..."
    cd "$TMP" || exit 1
    continue
  }
  
  git config user.email "chaos-engine@example.com"
  git config user.name "Chaos Engine"
  
  if ! git commit -m "Add blob data files (${FINAL_SIZE}MB)" -m "Generated by Chaos Engine testing suite."; then
    echo "❌ Failed to commit changes. Skipping..."
    cd "$TMP" || exit 1
    continue
  fi
  
  echo "Pushing changes to remote repository..."
  # Try up to 3 times in case of temporary connection issues
  MAX_PUSH_RETRIES=3
  for ((push_attempt=1; push_attempt<=MAX_PUSH_RETRIES; push_attempt++)); do
    if git push origin "$BRANCH_NAME"; then
      echo "✅ Successfully pushed changes to branch $BRANCH_NAME"
      break
    else
      if [[ $push_attempt -lt $MAX_PUSH_RETRIES ]]; then
        echo "⚠️ Push attempt $push_attempt failed. Retrying in 5 seconds..."
        sleep 5
      else
        echo "❌ Failed to push changes after $MAX_PUSH_RETRIES attempts. Skipping PR creation."
        cd "$TMP" || exit 1
        continue 2  # Continue the outer loop
      fi
    fi
  done
  
  # Create a pull request
  echo "Creating pull request..."
  
  # Try to get the default branch again (since we might have switched directories)
  if [[ -z "$DEFAULT_BRANCH" || "$DEFAULT_BRANCH" == "HEAD" ]]; then
    # Get the default branch from the API if git didn't provide one
    REPO_INFO=$(curl -k -s -X GET -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}")
    if echo "$REPO_INFO" | jq -e '.default_branch' > /dev/null; then
      DEFAULT_BRANCH=$(echo "$REPO_INFO" | jq -r '.default_branch')
      echo "Default branch from API: $DEFAULT_BRANCH"
    else
      # Fallback to main
      DEFAULT_BRANCH="main"
      echo "Using fallback default branch: $DEFAULT_BRANCH"
    fi
  fi
  
  # Create PR function
  create_pr() {
    local base_branch="$1"
    local pr_response
    
    echo "Attempting to create PR with base branch: $base_branch"
    pr_response=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/pulls" \
      -d "{\"title\":\"Add blob data files (${FINAL_SIZE}MB)\",\"body\":\"This PR adds sample blob data files for testing purposes. Total added data: ${FINAL_SIZE}MB.\",\"head\":\"${BRANCH_NAME}\",\"base\":\"${base_branch}\"}")
    
    if echo "$pr_response" | jq -e '.number' > /dev/null; then
      PR_NUMBER=$(echo "$pr_response" | jq -r '.number')
      echo "✅ Pull request #${PR_NUMBER} created with base '$base_branch'."
      return 0
    elif echo "$pr_response" | jq -e '.errors' > /dev/null; then
      ERROR_MSG=$(echo "$pr_response" | jq -r '.errors[0].message // "Unknown error"')
      echo "⚠️ Pull request creation failed: $ERROR_MSG"
      return 1
    else
      echo "ℹ️ Unexpected response when creating PR with base '$base_branch'."
      return 1
    fi
  }
  
  # Try to create PR with default branch first
  if create_pr "$DEFAULT_BRANCH"; then
    # Success!
    true
  else
    # Try common branch names as fallback
    PR_CREATED=false
    for branch in main master develop trunk; do
      # Skip if it's the same as the already-tried default branch
      if [[ "$branch" == "$DEFAULT_BRANCH" ]]; then
        continue
      fi
      
      echo "Trying with '$branch' as the base branch..."
      if create_pr "$branch"; then
        PR_CREATED=true
        break
      fi
    done
    
    if [[ "$PR_CREATED" != "true" ]]; then
      echo "ℹ️ Could not create PR with any branch. Changes are pushed to branch ${BRANCH_NAME}."
      # Try listing the branches from the API
      BRANCHES_RESPONSE=$(curl -k -s -X GET -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/branches?per_page=5")
      if echo "$BRANCHES_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
        echo "Available branches (first 5):"
        echo "$BRANCHES_RESPONSE" | jq -r '.[].name'
      fi
    fi
  fi
  
  # Clean up
  cd "$TMP" || exit 1
  
  echo "✅ Blob data added to ${ORG}/${REPO_NAME}"
done

# Collect and display final statistics
SUCCESSFUL_REPOS=${#PROCESSED_REPOS[@]}
TOTAL_SIZE=0
PR_COUNT=0
BRANCH_COUNT=0

echo -e "\n📊 Blob Data Creation Summary:"
echo "───────────────────────────────────────────────────────"

# Only attempt to collect stats if we processed any repos
if [[ $SUCCESSFUL_REPOS -gt 0 ]]; then
  # Get branch count using the GitHub API
  for REPO_NAME in "${PROCESSED_REPOS[@]}"; do
    # Count blob-data branches
    BRANCHES_RESPONSE=$(curl -k -s -X GET -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/branches?per_page=100")
    if echo "$BRANCHES_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
      REPO_BRANCH_COUNT=$(echo "$BRANCHES_RESPONSE" | jq -r '[.[] | select(.name | startswith("blob-data-"))] | length')
      BRANCH_COUNT=$((BRANCH_COUNT + REPO_BRANCH_COUNT))
    fi
    
    # Count PRs
    PRS_RESPONSE=$(curl -k -s -X GET -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/pulls?per_page=100")
    if echo "$PRS_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
      REPO_PR_COUNT=$(echo "$PRS_RESPONSE" | jq -r '[.[] | select(.title | startswith("Add blob data files"))] | length')
      PR_COUNT=$((PR_COUNT + REPO_PR_COUNT))
    fi
  done
fi

echo "✅ Repositories processed: ${SUCCESSFUL_REPOS}/${REPOS_TO_ADD}"
echo "✅ Blob data branches created: $BRANCH_COUNT"
echo "✅ Pull requests created: $PR_COUNT"
echo "✅ Target data size range: ${BLOB_MIN_SIZE}MB - ${BLOB_MAX_SIZE}MB per repository"
echo -e "\nTemporary workspace: $TMP (can be safely removed)"

echo -e "\n✅ create-blob-data module complete!"
