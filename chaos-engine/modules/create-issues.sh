#!/usr/bin/env bash
#
# issues reflect reality, comments reflect perception
#
####
set -euo pipefail

# modules/create-issues.sh
# Loads config from config.env and creates multiple issues with varied activities

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load global configuration
source "$ROOT_DIR/config.env"

# Determine API endpoint
if [[ "$GITHUB_SERVER_URL" == "https://github.com" ]]; then
  API="https://api.github.com"
else
  API="${GITHUB_SERVER_URL%/}/api/v3"
fi

# Prepare identifiers
TS=$(date +%s)
AUTH="Authorization: token ${GITHUB_TOKEN}"
TMP=$(mktemp -d)

echo "Creating $NUM_ISSUES issues across repositories in organization ${ORG}..."

# Get list of repositories in the organization
echo "Fetching repository list..."
REPOS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG}/repos?per_page=100")
REPO_NAMES=($(echo "$REPOS_JSON" | jq -r '.[].name'))

if [[ ${#REPO_NAMES[@]} -eq 0 ]]; then
  echo "No repositories found in organization ${ORG}"
  echo "Creating a test repository..."
  TEST_REPO="chaos-issues-test-${TS}"
  curl -k -s -X POST -H "$AUTH" "$API/orgs/${ORG}/repos" \
    -d "{\"name\":\"${TEST_REPO}\",\"auto_init\":true,\"private\":true}" >/dev/null
  REPO_NAMES=("$TEST_REPO")
  sleep 2
fi

# Issue title templates
ISSUE_TITLES=(
  "Bug: Application crashes when processing large files"
  "Feature Request: Add dark mode support"
  "Documentation: Update API reference for v2"
  "Performance: Optimize database queries for better response time"
  "Security: Fix XSS vulnerability in user input handling"
  "UI/UX: Improve mobile responsiveness of dashboard"
  "Refactor: Simplify authentication flow"
  "Test: Add integration tests for payment processing"
  "Dependency: Update to latest version of framework"
  "Configuration: Add support for environment-specific settings"
)

# Issue labels
LABEL_SETS=(
  "bug,high-priority,needs-triage"
  "enhancement,medium-priority,good-first-issue"
  "documentation,low-priority"
  "performance,high-priority"
  "security,critical"
)

# Issue states
STATES=("open" "closed")

# Generate markdown bodies of different complexity
generate_issue_body() {
  local complexity=$1
  local issue_num=$2
  local body=""

  case $complexity in
    simple)
      body="This is a simple issue created by Chaos Engine.\n\n- Point 1\n- Point 2\n- Point 3"
      ;;
    medium)
      body="## Issue Description\n\nThis issue was created by Chaos Engine for testing purposes.\n\n"
      body+="### Steps to Reproduce\n\n1. Step one\n2. Step two\n3. Step three\n\n"
      body+="### Expected Behavior\n\nThe system should respond within 200ms.\n\n"
      body+="### Actual Behavior\n\nThe system is taking over 2 seconds to respond.\n"
      ;;
    complex)
      # Use separate variable for each part of the body to avoid escape issues
      body="# Complex Issue ${issue_num}\n\n"
      body+="## Overview\n\n"
      body+="This is a complex issue created by Chaos Engine with various markdown features.\n\n"
      body+="## Technical Details\n\n"
      
      # Use simple code sample without json formatting
      body+="Example data:\n\n"
      body+="{\n"
      body+="  \"id\": ${issue_num},\n"
      body+="  \"created\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\n"
      body+="  \"status\": \"pending\"\n"
      body+="}\n\n"
      
      body+="## Additional Information\n\n"
      body+="| Property | Value |\n"
      body+="|----------|-------|\n"
      body+="| ID | ${issue_num} |\n"
      body+="| Created | $(date) |\n"
      body+="| Priority | High |\n\n"
      body+="- [x] Automated test case exists\n"
      body+="- [ ] Documentation updated\n"
      body+="- [ ] Release notes updated\n\n"
      body+="![Placeholder Image](https://via.placeholder.com/800x400?text=Issue+${issue_num})\n"
      ;;
  esac

  echo -e "$body"
}

# Comment templates
COMMENT_TEMPLATES=(
  "Thanks for reporting this issue. We're looking into it."
  "I can reproduce this on my system. Will investigate further."
  "This appears to be related to issue #%d. We should consider consolidating."
  "I've implemented a fix for this in PR #%d. Please review."
  "Can you provide more information about your environment?"
)

# Create issues distributed across repositories
for i in $(seq 1 "$NUM_ISSUES"); do
  # Select a repository (round-robin)
  REPO_IDX=$(( (i-1) % ${#REPO_NAMES[@]} ))
  REPO_NAME="${REPO_NAMES[$REPO_IDX]}"
  
  # Select issue properties
  TITLE_IDX=$(( (i-1) % ${#ISSUE_TITLES[@]} ))
  TITLE="${ISSUE_TITLES[$TITLE_IDX]} - Test ${i}"
  
  LABEL_SET_IDX=$(( (i-1) % ${#LABEL_SETS[@]} ))
  LABELS="${LABEL_SETS[$LABEL_SET_IDX]}"
  
  # Determine complexity based on issue number
  COMPLEXITY="simple"
  if [[ $(( i % 3 )) -eq 0 ]]; then
    COMPLEXITY="medium"
  elif [[ $(( i % 7 )) -eq 0 ]]; then
    COMPLEXITY="complex"
  fi
  
  # Determine state
  STATE=${STATES[$(( (i % ${#STATES[@]}) ))]}
  
  echo "   • Creating issue $i/$NUM_ISSUES in ${REPO_NAME}: ${TITLE} (${COMPLEXITY}, ${STATE})"
  
  # Create labels if they don't exist (first time for each repo)
  if [[ $i -le ${#REPO_NAMES[@]} ]]; then
    echo "     → Setting up labels for ${REPO_NAME}..."
    
    # Create bug label
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"bug","color":"d73a4a","description":"Something is not working"}' >/dev/null 2>&1 || true
    
    # Create enhancement label
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"enhancement","color":"a2eeef","description":"New feature or request"}' >/dev/null 2>&1 || true
    
    # Create documentation label
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"documentation","color":"0075ca","description":"Improvements to documentation"}' >/dev/null 2>&1 || true
    
    # Create priority labels
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"low-priority","color":"0e8a16","description":"Low priority issue"}' >/dev/null 2>&1 || true
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"medium-priority","color":"fbca04","description":"Medium priority issue"}' >/dev/null 2>&1 || true
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"high-priority","color":"d93f0b","description":"High priority issue"}' >/dev/null 2>&1 || true
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"critical","color":"b60205","description":"Critical priority issue"}' >/dev/null 2>&1 || true
    
    # Create other labels
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"good-first-issue","color":"7057ff","description":"Good for newcomers"}' >/dev/null 2>&1 || true
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"needs-triage","color":"c5def5","description":"Needs to be triaged"}' >/dev/null 2>&1 || true
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"performance","color":"0e8a16","description":"Performance related issue"}' >/dev/null 2>&1 || true
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/labels" \
      -d '{"name":"security","color":"d93f0b","description":"Security related issue"}' >/dev/null 2>&1 || true
  fi
  
  # Generate body based on complexity
  BODY=$(generate_issue_body "$COMPLEXITY" "$i")
  
  # Properly escape the body content for JSON
  BODY_ESCAPED=$(echo -n "$BODY" | jq -R -s '.')
  
  # Convert comma-separated labels to JSON array
  LABELS_JSON="["
  IFS=',' read -ra LABEL_ARRAY <<< "$LABELS"
  for idx in "${!LABEL_ARRAY[@]}"; do
    if [[ $idx -gt 0 ]]; then
      LABELS_JSON+=","
    fi
    LABELS_JSON+="\"${LABEL_ARRAY[$idx]}\""
  done
  LABELS_JSON+="]"
  
  # Create the issue with properly formatted JSON
  ISSUE_RESP=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/issues" \
    -d "{
      \"title\":\"${TITLE}\",
      \"body\":${BODY_ESCAPED},
      \"labels\":${LABELS_JSON}
    }")
  
  ISSUE_NUM=$(echo "$ISSUE_RESP" | jq -r '.number // empty')
  if [[ -z "$ISSUE_NUM" ]]; then
    echo "     ⚠ Failed to create issue: $(echo "$ISSUE_RESP" | jq -r '.message // "Unknown error"')"
    continue
  fi
  
  echo "     → Created issue #${ISSUE_NUM}"
  
  # Add comments (1-5 comments based on issue number)
  NUM_COMMENTS=$(( (i % 5) + 1 ))
  echo "     → Adding ${NUM_COMMENTS} comments..."
  
  for j in $(seq 1 "$NUM_COMMENTS"); do
    TEMPLATE_IDX=$(( (j-1) % ${#COMMENT_TEMPLATES[@]} ))
    COMMENT=$(printf "${COMMENT_TEMPLATES[$TEMPLATE_IDX]}" "$((i+j))" "$((i*2+j))")
    
    # Properly escape the comment for JSON
    COMMENT_ESCAPED=$(echo -n "$COMMENT" | jq -R -s '.')
    
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/issues/${ISSUE_NUM}/comments" \
      -d "{\"body\":${COMMENT_ESCAPED}}" >/dev/null
    sleep 1
  done
  
  # If complex issue, add a code sample as a comment
  if [[ "$COMPLEXITY" = "complex" ]]; then
    # Create the code comment in parts to avoid shell interpretation issues
    CODE_COMMENT="Here's a code sample that demonstrates the issue:"
    CODE_COMMENT+="\n\n\`\`\`javascript"
    CODE_COMMENT+="\nfunction demonstrateIssue() {"
    CODE_COMMENT+="\n  const data = fetchLargeDataset();"
    CODE_COMMENT+="\n  // This is inefficient and causes the crash"
    CODE_COMMENT+="\n  const processed = data.map(item => transformItem(item));"
    CODE_COMMENT+="\n  return processed.filter(item => item.isValid);"
    CODE_COMMENT+="\n}"
    CODE_COMMENT+="\n\`\`\`"
    
    # Properly escape the comment for JSON
    CODE_COMMENT_ESCAPED=$(echo -n "$CODE_COMMENT" | jq -R -s '.')
    
    curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/issues/${ISSUE_NUM}/comments" \
      -d "{\"body\":${CODE_COMMENT_ESCAPED}}" >/dev/null
  fi
  
  # Close issue if state should be closed
  if [[ "$STATE" = "closed" ]]; then
    echo "     → Closing issue..."
    curl -k -s -X PATCH -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/issues/${ISSUE_NUM}" \
      -d '{"state":"closed"}' >/dev/null
  fi
  
  # Add random reactions to some issues
  if [[ $(( i % 3 )) -eq 0 ]]; then
    echo "     → Adding reactions..."
    REACTIONS=("+1" "-1" "laugh" "confused" "heart" "hooray" "rocket" "eyes")
    NUM_REACTIONS=$(( (i % 3) + 1 ))
    
    for j in $(seq 1 "$NUM_REACTIONS"); do
      REACTION_IDX=$(( (i+j) % ${#REACTIONS[@]} ))
      REACTION="${REACTIONS[$REACTION_IDX]}"
      
      curl -k -s -X POST -H "$AUTH" -H "Accept: application/vnd.github.squirrel-girl-preview+json" \
        "$API/repos/${ORG}/${REPO_NAME}/issues/${ISSUE_NUM}/reactions" \
        -d "{\"content\":\"${REACTION}\"}" >/dev/null 2>&1 || true
      sleep 1
    done
  fi
  
  # Add milestone to some issues
  if [[ $(( i % 5 )) -eq 0 ]]; then
    echo "     → Creating and assigning milestone..."
    MILESTONE_NUM=$((i / 5))
    MILESTONE_TITLE="Release v0.${MILESTONE_NUM}.0"
    
    # Create milestone if it doesn't exist
    MILESTONE_ID=$(curl -k -s -X POST -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/milestones" \
      -d "{
        \"title\":\"${MILESTONE_TITLE}\",
        \"state\":\"open\",
        \"description\":\"Planned items for ${MILESTONE_TITLE}\"
      }" | jq -r '.number // empty')
    
    if [[ -n "$MILESTONE_ID" ]]; then
      curl -k -s -X PATCH -H "$AUTH" "$API/repos/${ORG}/${REPO_NAME}/issues/${ISSUE_NUM}" \
        -d "{\"milestone\":${MILESTONE_ID}}" >/dev/null
    fi
  fi
  
  echo "     ✓ Issue setup complete"
  sleep 1
done

echo "✅ create-issues module complete!"
