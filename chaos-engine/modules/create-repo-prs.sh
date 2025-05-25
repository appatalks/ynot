#!/usr/bin/env bash
#
# stand in the rain yet ask why wet
#
####
set -euo pipefail

# modules/create-repo-prs.sh
# Loads config from config.env and runs the repo + PR edge-case testing module

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

# Check if the organization exists
echo "Checking if organization ${ORG} exists..."
ORG_CHECK=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG}" | jq -r '.login // empty')
if [[ -z "$ORG_CHECK" ]]; then
  echo "⚠️ Organization ${ORG} does not exist."
  echo "Creating organization ${ORG}..."
  BILLING_EMAIL="${BILLING_EMAIL:-admin@example.com}"
  ORG_RESP=$(curl -k -s -X POST -H "$AUTH" "$API/admin/organizations" \
    -d "{\"login\":\"${ORG}\",\"admin\":\"${ADMIN_USERNAME:-$(curl -k -s -X GET -H "$AUTH" "$API/user" | jq -r '.login')}\",\"profile_name\":\"${ORG}\",\"billing_email\":\"${BILLING_EMAIL}\"}")
  
  if echo "$ORG_RESP" | jq -e '.login' > /dev/null; then
    echo "✅ Created organization: ${ORG}"
  else
    echo "❌ Failed to create organization. Response:"
    echo "$ORG_RESP" | jq '.'
    echo "Attempting to create repository directly in user namespace..."
    CURRENT_USER=$(curl -k -s -X GET -H "$AUTH" "$API/user" | jq -r '.login')
    if [[ -n "$CURRENT_USER" ]]; then
      echo "Using user namespace: $CURRENT_USER"
      export ORG="$CURRENT_USER"
    else
      echo "❌ Cannot determine user namespace. Exiting."
      exit 1
    fi
  fi
  sleep 2
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
  PR_NUMS+=("$PR_NUM")
  echo "     → PR #${PR_NUM}"
  git checkout main
  sleep 1
done

sleep 1

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
  sleep 2
  for j in 1 2 3; do
    echo "   • empty commit #$j"
    git commit --allow-empty -m "empty: trigger sync $j for PR #${PR_NUM}"
    git push origin "$BR"
    sleep 2
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
  sleep 1
  git commit --amend -m "feat: amended force push test for PR #${PR_NUM}"
  git push --force origin "$BR"
  sleep 1
  git commit --amend -m "feat: amended again force push test for PR #${PR_NUM}"
  git push --force origin "$BR"
  sleep 1
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
  sleep 1
  CURRENT_SHA=$(git rev-parse HEAD)
  curl -k -s -X PUT -H "$AUTH" "$API/repos/${ORG}/${REPO}/pulls/${PR_NUM}/update-branch" \
    -d "{\"expected_head_sha\":\"${CURRENT_SHA}\"}" >/dev/null &
  sleep 1
  git pull origin "$BR" >/dev/null 2>&1
  wait
  sleep 2
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
  sleep 1
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
for idx in "${!BRANCHES[@]}"; do
  BR="${BRANCHES[$idx]}"
  PR_NUM="${PR_NUMS[$idx]}"
  echo "   • PR #${PR_NUM} / branch $BR"
  git checkout "$BR"
  echo "refs test $(date)" > "refs.txt"
  git add "refs.txt"
  git commit -m "refs: test for PR #${PR_NUM}"
  git push origin "$BR"
  sleep 1
  echo "refs test 2 $(date)" > "refs2.txt"
  git add "refs2.txt"
  git commit -m "refs: test 2 for PR #${PR_NUM}"
  NEW_SHA=$(git rev-parse HEAD)
  curl -k -s -X PATCH -H "$AUTH" "$API/repos/${ORG}/${REPO}/git/refs/heads/${BR}" \
    -d "{\"sha\":\"${NEW_SHA}\",\"force\":true}" >/dev/null
  sleep 2
done

# Final summary
echo
echo "✅ create-repo-prs module complete!"
echo "Repository: ${GIT_URL_PREFIX}/${ORG}/${REPO}"
echo "Workspace: $TMP"
