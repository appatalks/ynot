#!/usr/bin/env bash
#
# stand in the rain yet ask why wet
#
####
set -euo pipefail

# modules/create-repo-prs.sh
# Loads config from config.env and runs the repo + PR edge-case testing module

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
    echo "     ℹ️ Running in noninteractive mode - automatically answering '${default_answer}'"
    REPLY="${default_answer}"
    return 0
  else
    echo "$prompt_text"
    read -p "       " -n 1 -r
    echo
    return 0
  fi
}

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load global configuration
source "$ROOT_DIR/config.env"

# Determine API endpoint and Git URL prefix
if [[ "$GITHUB_SERVER_URL" == "https://github.com" ]]; then
  API="https://api.github.com"
else
  API="${GITHUB_SERVER_URL%/}/api/v3"
fi
GIT_URL_PREFIX="$GITHUB_SERVER_URL"

# Prepare identifiers
TS=$(date +%s)
REPO="hook-edge-${TS}"
TMP=$(mktemp -d)
AUTH="Authorization: token ${GITHUB_TOKEN}"

# Check for API rate limit issues before starting
RATE_LIMIT_INFO=$(curl -k -s -X GET -H "$AUTH" "$API/rate_limit")
CORE_REMAINING=$(echo "$RATE_LIMIT_INFO" | jq -r '.resources.core.remaining // 5000')
CORE_RESET=$(echo "$RATE_LIMIT_INFO" | jq -r '.resources.core.reset // 0')
CORE_RESET_TIME=$(date -d "@$CORE_RESET" 2>/dev/null || date -r "$CORE_RESET" 2>/dev/null || echo "Unknown time")

echo "GitHub API rate limit status: $CORE_REMAINING requests remaining (resets at $CORE_RESET_TIME)"
if [[ "$CORE_REMAINING" -lt 100 ]]; then
  echo "⚠️ Warning: GitHub API rate limit is low ($CORE_REMAINING remaining)."
  echo "    Creating PRs may fail due to rate limiting."
  echo "    Rate limit will reset at: $CORE_RESET_TIME"
  
  # If very close to limit, ask for confirmation
  if [[ "$CORE_REMAINING" -lt 20 ]]; then
    echo "⚠️ Rate limit critically low! Consider waiting until the rate limit resets."
    prompt_user "Do you want to continue anyway? (y/n) " "y"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborting PR creation. Try again after rate limit reset."
      exit 0
    fi
  fi
fi

# Check if the organization exists with enhanced retry logic
echo "Checking if organization ${ORG} exists..."
MAX_RETRIES=15 # Extended retries to give org creation more time
RETRY_COUNT=0
ORG_EXISTS=false
RETRY_DELAY=4 # In seconds, gradually increasing

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
  ORG_CHECK=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG}" | jq -r '.login // empty')
  if [[ -n "$ORG_CHECK" ]]; then
    echo "✅ Organization ${ORG} exists."
    ORG_EXISTS=true
    # Wait a bit more to ensure organization is fully provisioned
    echo "   Waiting 5 seconds to ensure organization is fully provisioned..."
    sleep 5
    break
  else
    RETRY_COUNT=$((RETRY_COUNT+1))
    # Increase delay with each retry (backoff strategy)
    CURRENT_DELAY=$((RETRY_DELAY * (RETRY_COUNT / 2 + 1)))
    echo "⚠️ Organization ${ORG} does not yet exist. Retry $RETRY_COUNT of $MAX_RETRIES..."
    echo "   Waiting ${CURRENT_DELAY} seconds before next attempt..."
    sleep "${CURRENT_DELAY}"
  fi
done

# If the organization still doesn't exist after retries, try to create it
if [[ "$ORG_EXISTS" != "true" ]]; then
  echo "⚠️ Organization ${ORG} does not exist after $MAX_RETRIES attempts."
  
  # Ask before creating (respect noninteractive mode)
  prompt_user "Would you like to try creating the organization? (y/n) " "y"
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Organization creation skipped. Exiting."
    exit 1
  fi
  
  echo "Creating organization ${ORG}..."
  BILLING_EMAIL="${BILLING_EMAIL:-admin@example.com}"
  ADMIN_USER=${ADMIN_USERNAME:-$(curl -k -s -X GET -H "$AUTH" "$API/user" | jq -r '.login')}
  
  # Show more detailed information for debugging
  echo "   → Using admin user: $ADMIN_USER for organization creation"
  echo "   → Using billing email: $BILLING_EMAIL"
  
  # Try to create the organization with retry logic
  MAX_CREATE_RETRIES=3
  CREATE_RETRY_COUNT=0
  ORG_CREATED=false
  
  while [[ $CREATE_RETRY_COUNT -lt $MAX_CREATE_RETRIES ]]; do
    ORG_RESP=$(curl -k -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
      -w "\n\nHTTP_STATUS:%{http_code}" \
      "$API/admin/organizations" \
      -d "{\"login\":\"${ORG}\",\"admin\":\"${ADMIN_USER}\",\"profile_name\":\"${ORG}\",\"billing_email\":\"${BILLING_EMAIL}\"}")
      
    # Extract HTTP status code
    HTTP_STATUS=$(echo "$ORG_RESP" | grep -o "HTTP_STATUS:[0-9]*" | cut -d':' -f2)
    # Extract the JSON response part
    JSON_RESP=$(echo "$ORG_RESP" | sed -n '/HTTP_STATUS/!p')
    
    echo "   → HTTP Status: $HTTP_STATUS"
    
    if [[ "$HTTP_STATUS" == "2"* ]] && echo "$JSON_RESP" | jq -e '.login' > /dev/null; then
      echo "✅ Created organization: ${ORG}"
      # Wait for the organization to be fully created in the system
      echo "   Waiting 10 seconds to ensure organization is fully provisioned..."
      sleep 10
      ORG_CREATED=true
      break
    else
      CREATE_RETRY_COUNT=$((CREATE_RETRY_COUNT+1))
      echo "⚠️ Failed to create organization. Retry $CREATE_RETRY_COUNT of $MAX_CREATE_RETRIES..."
      echo "   Error: $(echo "$JSON_RESP" | jq -r '.message // "Unknown error"')"
      
      if [[ $CREATE_RETRY_COUNT -lt $MAX_CREATE_RETRIES ]]; then
        echo "   Waiting 5 seconds before retry..."
        sleep 5
      fi
    fi
  done
  
  # If we couldn't create the organization, fall back to user namespace
  if [[ "$ORG_CREATED" != "true" ]]; then
    echo "❌ Failed to create organization after $MAX_CREATE_RETRIES attempts."
    echo "Attempting to create repository directly in user namespace..."
    CURRENT_USER=$(curl -k -s -X GET -H "$AUTH" "$API/user" | jq -r '.login')
    if [[ -n "$CURRENT_USER" ]]; then
      echo "Using user namespace: $CURRENT_USER"
      export ORG="$CURRENT_USER"
      # Ask before proceeding
      prompt_user "Use user namespace instead? (y/n) " "y"
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborting. Please check organization settings and try again."
        exit 1
      fi
    else
      echo "❌ Cannot determine user namespace. Exiting."
      exit 1
    fi
  fi
fi

# 1) Create new repo
echo "1) Create new repo ${ORG}/${REPO}..."
REPO_RESP=$(curl -k -s -X POST -H "$AUTH" "$API/orgs/${ORG}/repos" \
  -d "{\"name\":\"${REPO}\",\"auto_init\":true,\"private\":true}")

if echo "$REPO_RESP" | jq -e '.name' > /dev/null; then
  echo "✅ Repository created: ${ORG}/${REPO}"
else
  echo "❌ Failed to create repository. Response:"
  echo "$REPO_RESP" | jq '.'
  exit 1
fi
sleep 2

# 2) Register webhook
echo "2) Register webhook (push + pull_request)..."
HOOK_ID=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO}/hooks" \
  -d "{\"name\":\"web\",\"active\":true,\"events\":[\"push\",\"pull_request\"],\"config\":{\"url\":\"${WEBHOOK_URL}\",\"content_type\":\"json\"}}" \
  | jq -r .id)
sleep 2

# 3) Clone & prepare main
echo "3) Clone & prepare main..."
git clone "https://x-access-token:${GITHUB_TOKEN}@${GIT_URL_PREFIX#https://}/${ORG}/${REPO}.git" "$TMP"
cd "$TMP"
# Ensure remote uses PAT
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@${GIT_URL_PREFIX#https://}/${ORG}/${REPO}.git"
git checkout main

# 4) Create feature branches & open PRs
echo "4) Create $NUM_PRS feature branches & open PRs..."
declare -a PR_NUMS BRANCHES

# Create only the number of PRs specified in NUM_PRS
for i in $(seq 1 "$NUM_PRS"); do
  BR="feat-${TS}-${i}"
  BRANCHES+=("$BR")
  echo "   • branch $BR"
  git checkout -b "$BR"
  echo "initial content for PR $i" > "pr${i}.txt"
  git add "pr${i}.txt"
  git commit -m "chore: seed PR $i"
  git push -u origin "$BR"
  PR_NUM=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO}/pulls" \
    -d "{\"title\":\"Edge Case Test PR #${i}\",\"head\":\"${BR}\",\"base\":\"main\"}" \
    | jq -r .number)
  
  # Check if PR was created successfully
  if [[ -z "$PR_NUM" || "$PR_NUM" == "null" ]]; then
    echo "     ⚠️ Failed to create PR for branch $BR. Retrying..."
    # Retry once after a short delay
    sleep 2
    PR_NUM=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO}/pulls" \
      -d "{\"title\":\"Edge Case Test PR #${i}\",\"head\":\"${BR}\",\"base\":\"main\"}" \
      | jq -r .number)
      
    if [[ -z "$PR_NUM" || "$PR_NUM" == "null" ]]; then
      echo "     ❌ Failed to create PR after retry. Skipping."
      continue
    fi
  fi
  
  PR_NUMS+=("$PR_NUM")
  echo "     → PR #${PR_NUM}"
  git checkout main
  sleep 1
done

sleep 1

# Check if we should run the edge case approaches
if [[ "${RUN_PR_APPROACHES:-false}" == "true" ]]; then
  echo
  echo "RUN_PR_APPROACHES is set to true - running all PR stress test approaches"
  echo
  # APPROACH 1: Empty commits + push
  echo "=== APPROACH 1: Empty commits + push ==="
  for idx in "${!BRANCHES[@]}"; do
    BR="${BRANCHES[$idx]}"
    PR_NUM="${PR_NUMS[$idx]}"
    echo "   • PR #${PR_NUM} / branch $BR"
    git checkout "$BR"
    echo "real content change $(date)" > "real-change.txt"
    git add "real-change.txt"
    git commit -m "feat: real change for PR #${PR_NUM}"
    git push origin "$BR"
    sleep 0.5
    for j in 1 2 3; do
      echo "   • empty commit #$j"
      git commit --allow-empty -m "empty: trigger sync $j for PR #${PR_NUM}"
      git push origin "$BR"
      sleep 0.5
    done
  done

  sleep 1

  echo
  # APPROACH 2: Force push patterns
  echo "=== APPROACH 2: Force push patterns ==="
  for idx in "${!BRANCHES[@]}"; do
    BR="${BRANCHES[$idx]}"
    PR_NUM="${PR_NUMS[$idx]}"
    echo "   • PR #${PR_NUM} / branch $BR"
    git checkout "$BR"
    echo "force push test $(date)" > "force-test.txt"
    git add "force-test.txt"
    git commit -m "feat: force push test for PR #${PR_NUM}"
    git push origin "$BR"
    sleep 0.5
    git commit --amend -m "feat: amended force push test for PR #${PR_NUM}"
    git push --force origin "$BR"
    sleep 0.5
    git commit --amend -m "feat: amended again force push test for PR #${PR_NUM}"
    git push --force origin "$BR"
    sleep 0.5
  done
  sleep 2

  echo
  # APPROACH 3: Rapid concurrent operations
  echo "=== APPROACH 3: Rapid concurrent operations ==="
  for idx in "${!BRANCHES[@]}"; do
    BR="${BRANCHES[$idx]}"
    PR_NUM="${PR_NUMS[$idx]}"
    echo "   • PR #${PR_NUM} / branch $BR"
    git checkout "$BR"
    echo "rapid test $(date)" > "rapid-test.txt"
    git add "rapid-test.txt"
    git commit -m "feat: rapid test for PR #${PR_NUM}"
    git push origin "$BR" &
    curl -k -s -X PUT -H "$AUTH" "$API/repos/${ORG}/${REPO}/contents/concurrent-${PR_NUM}.txt" \
      -d "{\"message\":\"concurrent: main update ${PR_NUM}\",\"content\":\"$(echo "Concurrent ${PR_NUM}" | base64)\"}" >/dev/null &
    wait
    sleep 0.5
    CURRENT_SHA=$(git rev-parse HEAD)
    curl -k -s -X PUT -H "$AUTH" "$API/repos/${ORG}/${REPO}/pulls/${PR_NUM}/update-branch" \
      -d "{\"expected_head_sha\":\"${CURRENT_SHA}\"}" >/dev/null &
    sleep 0.5
    git pull origin "$BR" >/dev/null 2>&1
    wait
    sleep 0.5
  done
  sleep 2

  echo
  # APPROACH 4: Rebase operations
  echo "=== APPROACH 4: Rebase operations ==="
  for idx in "${!BRANCHES[@]}"; do
    BR="${BRANCHES[$idx]}"
    PR_NUM="${PR_NUMS[$idx]}"
    echo "   • PR #${PR_NUM} / branch $BR"
    git checkout "$BR"
    echo "rebase1 $(date)" > "rebase1.txt"
    git add "rebase1.txt"
    git commit -m "rebase: commit 1 for PR #${PR_NUM}"
    echo "rebase2 $(date)" > "rebase2.txt"
    git add "rebase2.txt"
    git commit -m "rebase: commit 2 for PR #${PR_NUM}"
    git push origin "$BR"
    sleep 0.5
    git reset --hard HEAD~2
    echo "rebased content $(date)" > "rebased.txt"
    git add "rebased.txt"
    git commit -m "rebase: squashed commits for PR #${PR_NUM}"
  git push --force origin "$BR"
  sleep 1
  done
  sleep 2

  echo
  # APPROACH 5: Direct refs manipulation
  echo "=== APPROACH 5: Direct refs manipulation ==="
  for idx in "${!BRANCHES[@]}"; do    BR="${BRANCHES[$idx]}"
    PR_NUM="${PR_NUMS[$idx]}"
    echo "   • PR #${PR_NUM} / branch $BR"
    git checkout "$BR"
    echo "refs test $(date)" > "refs.txt"
    git add "refs.txt"
    git commit -m "refs: test for PR #${PR_NUM}"
    git push origin "$BR"
    sleep 0.5
    echo "refs test 2 $(date)" > "refs2.txt"
    git add "refs2.txt"
    git commit -m "refs: test 2 for PR #${PR_NUM}"
    NEW_SHA=$(git rev-parse HEAD)
    curl -k -s -X PATCH -H "$AUTH" "$API/repos/${ORG}/${REPO}/git/refs/heads/${BR}" \
      -d "{\"sha\":\"${NEW_SHA}\",\"force\":true}" >/dev/null
    sleep 1
  done
fi

# Final summary
echo
echo "✅ create-repo-prs module complete!"
echo "Repository: ${GIT_URL_PREFIX}/${ORG}/${REPO}"
echo "Workspace: $TMP"
