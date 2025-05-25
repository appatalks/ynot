#!/usr/bin/env bash
#
# structure amid chaos, patterns that repeat yet evolve
#
####
set -euo pipefail

# modules/create-repositories.sh
# Loads config from config.env and creates multiple repositories with varied settings

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
AUTH="Authorization: token ${GITHUB_TOKEN}"
REPO_PREFIX="chaos-repo"
TMP=$(mktemp -d)

echo "Creating $NUM_REPOS repositories in organization ${ORG}..."

# Repository visibility options
VISIBILITIES=("public" "private" "internal")
# Repository template options - simple templates for test content
TEMPLATES=(
  "empty|No template"
  "readme|README only"
  "full|README, LICENSE, and .gitignore"
)
# Branch protection patterns
PROTECTION_PATTERNS=(
  "none"
  "require_reviews"
  "require_status_checks"
  "full_protection"
)

for i in $(seq 1 "$NUM_REPOS"); do
  REPO_NAME="${REPO_PREFIX}-${TS}-${i}"
  # Rotate through visibility options
  VISIBILITY=${VISIBILITIES[$(( (i-1) % ${#VISIBILITIES[@]} ))]}
  # Rotate through template options
  TEMPLATE_IDX=$(( (i-1) % ${#TEMPLATES[@]} ))
  TEMPLATE_TYPE=${TEMPLATES[$TEMPLATE_IDX]%%|*}
  
  echo "   • Creating repository $i/$NUM_REPOS: $REPO_NAME (${VISIBILITY}, template: ${TEMPLATE_TYPE})"
  
  # Create repository with varied settings
  RESP=$(curl -k -s -X POST -H "$AUTH" "$API/orgs/${ORG}/repos" \
    -d "{
      \"name\":\"${REPO_NAME}\",
      \"description\":\"Chaos Engine test repo ${i}\",
      \"homepage\":\"${GIT_URL_PREFIX}/${ORG}/${REPO_NAME}\",
      \"private\":$([ "$VISIBILITY" = "private" ] && echo "true" || echo "false"),
      \"visibility\":\"${VISIBILITY}\",
      \"has_issues\":true,
      \"has_projects\":$(( i % 2 )),
      \"has_wiki\":$(( (i+1) % 2 )),
      \"auto_init\":$([ "$TEMPLATE_TYPE" != "empty" ] && echo "true" || echo "false"),
      \"allow_squash_merge\":true,
      \"allow_merge_commit\":$(( i % 2 )),
      \"allow_rebase_merge\":$(( (i+1) % 2 )),
      \"delete_branch_on_merge\":$(( (i+2) % 2 ))
    }")
  
  REPO_ID=$(echo "$RESP" | jq -r '.id // empty')
  if [[ -z "$REPO_ID" ]]; then
    echo "     ⚠ Failed to create repository: $(echo "$RESP" | jq -r '.message // "Unknown error"')"
    continue
  fi
  
  echo "     → Created repository ID: $REPO_ID"
  sleep 2
  
  # Clone the repository if needed to add content
  if [[ "$TEMPLATE_TYPE" != "empty" ]]; then
    echo "     → Initializing repository content..."
    CLONE_DIR="${TMP}/${REPO_NAME}"
    mkdir -p "$CLONE_DIR"
    git clone "https://x-access-token:${GITHUB_TOKEN}@${GIT_URL_PREFIX#https://}/${ORG}/${REPO_NAME}.git" "$CLONE_DIR"
    cd "$CLONE_DIR"
    
    # Create README if it doesn't exist
    if [[ ! -f "README.md" ]]; then
      cat > "README.md" << EOF
# ${REPO_NAME}

This is a test repository created by the Chaos Engine testing suite on $(date).

## Purpose

This repository demonstrates various GitHub features and API capabilities.

## Structure

The repository contains sample files to test various GitHub workflows.
EOF
      git add "README.md"
      git commit -m "chore: add README"
    fi
    
    # Add LICENSE if full template
    if [[ "$TEMPLATE_TYPE" = "full" && ! -f "LICENSE" ]]; then
      cat > "LICENSE" << EOF
MIT License

Copyright (c) $(date +%Y) Chaos Engine Testing Suite

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
      git add "LICENSE"
      git commit -m "chore: add LICENSE"
    fi
    
    # Add .gitignore if full template
    if [[ "$TEMPLATE_TYPE" = "full" && ! -f ".gitignore" ]]; then
      cat > ".gitignore" << EOF
# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Dependencies
node_modules/
vendor/
.env

# Build artifacts
dist/
build/
*.tgz
*.tar.gz

# OS specific files
.DS_Store
Thumbs.db
EOF
      git add ".gitignore"
      git commit -m "chore: add gitignore"
    fi
    
    # Push changes if we made any
    if [[ $(git log --oneline origin/main..HEAD | wc -l) -gt 0 ]]; then
      git push origin main
    fi
    
    # Create some sample branches
    for j in $(seq 1 3); do
      BRANCH_NAME="feature-${j}"
      git checkout -b "$BRANCH_NAME"
      mkdir -p "src/module-${j}"
      cat > "src/module-${j}/index.js" << EOF
/**
 * Sample module ${j}
 * Created by Chaos Engine
 */
function helloWorld${j}() {
  console.log("Hello from module ${j}!");
  return ${j};
}

module.exports = { helloWorld${j} };
EOF
      git add "src/module-${j}"
      git commit -m "feat: add module ${j}"
      git push origin "$BRANCH_NAME"
      git checkout main
    done
    
    cd "$TMP"
  fi
  
  # Set up branch protection on main branch for some repos
  PROTECTION_TYPE=${PROTECTION_PATTERNS[$(( (i-1) % ${#PROTECTION_PATTERNS[@]} ))]}
  if [[ "$PROTECTION_TYPE" != "none" ]]; then
    echo "     → Setting up branch protection (${PROTECTION_TYPE})..."
    
    # Base protection settings
    PROTECTION_PAYLOAD="{\"required_status_checks\":null,\"enforce_admins\":false,\"required_pull_request_reviews\":null,\"restrictions\":null}"
    
    # Customize based on protection type
    case "$PROTECTION_TYPE" in
      require_reviews)
        PROTECTION_PAYLOAD="{
          \"required_status_checks\":null,
          \"enforce_admins\":false,
          \"required_pull_request_reviews\":{
            \"dismissal_restrictions\":{},
            \"dismiss_stale_reviews\":true,
            \"require_code_owner_reviews\":false,
            \"required_approving_review_count\":1
          },
          \"restrictions\":null
        }"
        ;;
      require_status_checks)
        PROTECTION_PAYLOAD="{
          \"required_status_checks\":{
            \"strict\":true,
            \"contexts\":[\"ci/jenkins\", \"security/scan\"]
          },
          \"enforce_admins\":false,
          \"required_pull_request_reviews\":null,
          \"restrictions\":null
        }"
        ;;
      full_protection)
        PROTECTION_PAYLOAD="{
          \"required_status_checks\":{
            \"strict\":true,
            \"contexts\":[\"ci/jenkins\", \"security/scan\"]
          },
          \"enforce_admins\":true,
          \"required_pull_request_reviews\":{
            \"dismissal_restrictions\":{},
            \"dismiss_stale_reviews\":true,
            \"require_code_owner_reviews\":true,
            \"required_approving_review_count\":2
          },
          \"restrictions\":{
            \"users\":[],
            \"teams\":[],
            \"apps\":[]
          }
        }"
        ;;
    esac
    
    curl -k -s -X PUT -H "$AUTH" \
      "$API/repos/${ORG}/${REPO_NAME}/branches/main/protection" \
      -d "$PROTECTION_PAYLOAD" >/dev/null
  fi
  
  # Create webhook for the repository
  echo "     → Creating repository webhook..."
  HOOK_ID=$(curl -k -s -X POST -H "$AUTH" \
    "$API/repos/${ORG}/${REPO_NAME}/hooks" \
    -d "{
      \"name\":\"web\",
      \"active\":true,
      \"events\":[\"push\",\"pull_request\",\"issues\"],
      \"config\":{
        \"url\":\"${WEBHOOK_URL}\",
        \"content_type\":\"json\",
        \"insecure_ssl\":\"1\"
      }
    }" | jq -r '.id // "0"')
  
  if [[ "$HOOK_ID" != "0" && -n "$HOOK_ID" ]]; then
    echo "       → Webhook ID: $HOOK_ID"
  else
    echo "       ⚠ Failed to create webhook"
  fi
  
  # Create some tags if this is a full template repository
  if [[ "$TEMPLATE_TYPE" = "full" ]]; then
    echo "     → Creating tags..."
    cd "${TMP}/${REPO_NAME}"
    for j in $(seq 1 3); do
      TAG_NAME="v0.${j}.0"
      git tag -a "$TAG_NAME" -m "Release v0.${j}.0"
      git push origin "$TAG_NAME"
      
      # Create a release for some tags
      if [[ $((j % 2)) -eq 0 ]]; then
        echo "       → Creating release for $TAG_NAME..."
        curl -k -s -X POST -H "$AUTH" \
          "$API/repos/${ORG}/${REPO_NAME}/releases" \
          -d "{
            \"tag_name\":\"${TAG_NAME}\",
            \"name\":\"Release ${TAG_NAME}\",
            \"body\":\"This is release ${TAG_NAME} created by Chaos Engine.\",
            \"draft\":false,
            \"prerelease\":false
          }" >/dev/null
      fi
    done
  fi
  
  echo "     ✓ Repository setup complete"
  sleep 2
done

echo "✅ create-repositories module complete!"
echo "Created $NUM_REPOS repositories with prefixes: ${REPO_PREFIX}-${TS}-*"
echo "Workspace: $TMP"
