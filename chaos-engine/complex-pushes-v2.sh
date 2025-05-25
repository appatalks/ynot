#!/usr/bin/env bash
####
# Create a webhook to monitor & simulate a group of complex but common pull request events. 
# -- stand in the rain yet ask why wet...
#### 

set -euo pipefail

# Set Env
GITHUB_TOKEN="ghp_****"

export ORG="MY-ORG"
export WEBHOOK_URL="https://smee.io/****"
export GITHUB_SERVER_URL="https://git.example.com"  # Comment for GHEC
export NUM_PRS=3  # Number of PRs to create

# Non-interactive Git config: disable SSL verify, disable prompts, and disable credential helper
export GIT_SSL_NO_VERIFY=true
export GIT_TERMINAL_PROMPT=0
git config --global credential.helper ""

# Determine if we're using GitHub.com or GitHub Enterprise Server
if [[ "$GITHUB_SERVER_URL" == "https://github.com" ]]; then
  API="https://api.github.com"
  GIT_URL_PREFIX="https://github.com"
  echo "Using GitHub.com"
else
  GITHUB_SERVER_URL="${GITHUB_SERVER_URL%/}"
  API="${GITHUB_SERVER_URL}/api/v3"
  GIT_URL_PREFIX="$GITHUB_SERVER_URL"
  echo "Using GitHub Enterprise Server: $GITHUB_SERVER_URL"
fi

TS=$(date +%s)
REPO="hook-edge-${TS}"
TMP=$(mktemp -d)
AUTH="Authorization: token ${GITHUB_TOKEN}"

# 1) Create new repo (with initial main)
echo "1) Create new repo ${ORG}/${REPO} (with initial main)"
curl -k -s -X POST -H "$AUTH" "$API/orgs/${ORG}/repos" \
  -d "{\"name\":\"${REPO}\",\"auto_init\":true,\"private\":true}" >/dev/null
sleep 2

# 2) Register webhook (push + pull_request)
echo "2) Register webhook (push + pull_request)"
HOOK_ID=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO}/hooks" \
  -d '{
    "name":"web",
    "active":true,
    "events":["push","pull_request"],
    "config":{
      "url":"'"${WEBHOOK_URL}"'",
      "content_type":"json"
    }
  }' | jq -r .id)
sleep 2

# 3) Clone & prepare main
echo "3) Clone & prepare main"
git clone "https://x-access-token:${GITHUB_TOKEN}@${GIT_URL_PREFIX#https://}/${ORG}/${REPO}.git" "$TMP"
cd "$TMP"
# Ensure remote uses embedded PAT
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@${GIT_URL_PREFIX#https://}/${ORG}/${REPO}.git"
git checkout main

# 4) Create feature branches & open PRs
echo "4) Create ${NUM_PRS} feature branches & open PRs"
declare -a PR_NUMS
declare -a BRANCHES
for i in $(seq 1 $NUM_PRS); do
  BRANCH="feat-${TS}-${i}"
  BRANCHES+=("$BRANCH")

  echo "   Creating branch ${BRANCH}..."
  git checkout -b "$BRANCH"
  echo "initial content for PR $i" > "pr${i}.txt"
  git add "pr${i}.txt"
  git commit -m "chore: seed PR $i"
  git push -u origin "$BRANCH"

  PR_NUM=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO}/pulls" \
    -d "{\"title\":\"Edge Case Test PR #${i}\",\"head\":\"${BRANCH}\",\"base\":\"main\"}" \
    | jq -r .number)
  PR_NUMS+=("$PR_NUM")
  echo "   → PR #${PR_NUM} created for branch ${BRANCH}"

  git checkout main
  sleep 2
done

sleep 3

echo
# EDGE CASE TESTING: Multiple approaches to trigger specific sequences
echo "=== EDGE CASE TESTING: Multiple approaches to trigger specific sequences ==="

# APPROACH 1: Empty commits + push
echo "5) APPROACH 1: Empty commits and strategic operations"
for i in $(seq 1 $NUM_PRS); do
  BRANCH="${BRANCHES[$((i-1))]}"
  PR_NUM="${PR_NUMS[$((i-1))]}"

  echo "   Testing empty commits on PR #${PR_NUM} (${BRANCH})..."
  git checkout "$BRANCH"

  # Real commit
  echo "real content change $(date)" > "real-change-pr${i}.txt"
  git add "real-change-pr${i}.txt"
  git commit -m "feat: real change for PR $i"
  git push origin "$BRANCH"
  sleep 2

  # Empty commits
  for j in 1 2 3; do
    echo "   Adding empty commit ${j}..."
    git commit --allow-empty -m "empty: trigger sync ${j} for PR $i"
    git push origin "$BRANCH"
    sleep 2
  done
done

sleep 5

# APPROACH 2: Force push scenarios
echo "6) APPROACH 2: Force push patterns"
for i in $(seq 1 $NUM_PRS); do
  BRANCH="${BRANCHES[$((i-1))]}"
  PR_NUM="${PR_NUMS[$((i-1))]}"

  echo "   Testing force push patterns on PR #${PR_NUM} (${BRANCH})..."
  git checkout "$BRANCH"

  # Commit + push
  echo "force push test $(date)" > "force-test-pr${i}.txt"
  git add "force-test-pr${i}.txt"
  git commit -m "feat: force push test for PR $i"
  git push origin "$BRANCH"
  sleep 2

  # Amend + force push twice
  for k in 1 2; do
    git commit --amend -m "feat: amended${k:+ again} force push test for PR $i"
    git push --force origin "$BRANCH"
    sleep 2
  done
done

sleep 5

# APPROACH 3: Rapid concurrent main updates with PR syncs
echo "7) APPROACH 3: Rapid concurrent operations (race condition simulation)"
for i in $(seq 1 $NUM_PRS); do
  BRANCH="${BRANCHES[$((i-1))]}"
  PR_NUM="${PR_NUMS[$((i-1))]}"

  echo "   Testing rapid operations on PR #${PR_NUM} (${BRANCH})..."
  git checkout "$BRANCH"

  echo "rapid test $(date)" > "rapid-pr${i}.txt"
  git add "rapid-pr${i}.txt"
  git commit -m "feat: rapid test for PR $i"
  git push origin "$BRANCH" &

  # Concurrent main update
  curl -k -s -X PUT -H "$AUTH" "$API/repos/${ORG}/${REPO}/contents/concurrent-${i}.txt" \
    -d "{\"message\":\"concurrent: main update $i\",\"content\":\"$(echo "Concurrent $i" | base64)\"}" >/dev/null &

  wait
  sleep 1

  CURRENT_SHA=$(git rev-parse HEAD)
  curl -k -s -X PUT -H "$AUTH" "$API/repos/${ORG}/${REPO}/pulls/${PR_NUM}/update-branch" \
    -d "{\"expected_head_sha\":\"${CURRENT_SHA}\"}" >/dev/null &

  sleep 1
  git pull origin "$BRANCH" >/dev/null 2>&1
  wait
  sleep 2
done

sleep 5

# APPROACH 4: Rebase operations
echo "8) APPROACH 4: Rebase operations"
for i in $(seq 1 $NUM_PRS); do
  BRANCH="${BRANCHES[$((i-1))]}"
  PR_NUM="${PR_NUMS[$((i-1))]}"

  echo "   Testing rebase operations on PR #${PR_NUM} (${BRANCH})..."
  git checkout "$BRANCH"

  echo "rebase1 $(date)" > "rebase1-pr${i}.txt"
  git add "rebase1-pr${i}.txt"
  git commit -m "rebase: commit 1 for PR $i"

  echo "rebase2 $(date)" > "rebase2-pr${i}.txt"
  git add "rebase2-pr${i}.txt"
  git commit -m "rebase: commit 2 for PR $i"

  git push origin "$BRANCH"
  sleep 2

  # Squash via reset + commit
  git reset --hard HEAD~2
  echo "rebased content $(date)" > "rebased-pr${i}.txt"
  git add "rebased-pr${i}.txt"
  git commit -m "rebase: squashed commits for PR $i"
  git push --force origin "$BRANCH"
  sleep 2
done

sleep 5

# APPROACH 5: Direct refs manipulation
echo "9) APPROACH 5: Direct refs manipulation"
for i in $(seq 1 $NUM_PRS); do
  BRANCH="${BRANCHES[$((i-1))]}"
  PR_NUM="${PR_NUMS[$((i-1))]}"

  echo "   Testing refs manipulation on PR #${PR_NUM} (${BRANCH})..."
  git checkout "$BRANCH"

  echo "refs test $(date)" > "refs-pr${i}.txt"
  git add "refs-pr${i}.txt"
  git commit -m "refs: test for PR $i"
  git push origin "$BRANCH"
  sleep 2

  COMMIT_SHA=$(git rev-parse HEAD)
  echo "refs test 2 $(date)" > "refs2-pr${i}.txt"
  git add "refs2-pr${i}.txt"
  git commit -m "refs: test 2 for PR $i"
  NEW_SHA=$(git rev-parse HEAD)

  curl -k -s -X PATCH -H "$AUTH" "$API/repos/${ORG}/${REPO}/git/refs/heads/${BRANCH}" \
    -d "{\"sha\":\"${NEW_SHA}\",\"force\":true}" >/dev/null
  sleep 3
done

# Final summary after testing

echo
**✅ Edge case testing complete!**
echo "Check webhook deliveries for the following patterns:"
echo "🎯 TARGET: push -> pull_request.synchronize -> pull_request.synchronize -> pull_request.synchronize"

echo
echo "Tested approaches:"
echo "  1. Empty commits"
echo "  2. Force push patterns"
echo "  3. Rapid concurrent operations"
echo "  4. Rebase operations"
echo "  5. Direct refs manipulation"

echo
echo "Created PRs:"
for i in $(seq 1 $NUM_PRS); do
  echo "  PR #${PR_NUMS[$((i-1))]} (${BRANCHES[$((i-1))]}): ${GIT_URL_PREFIX}/${ORG}/${REPO}/pull/${PR_NUMS[$((i-1))]}"
done

echo
echo "Repo: ${GIT_URL_PREFIX}/${ORG}/${REPO}"
echo "Workdir: $TMP"
