#!/usr/bin/env bash
#
# entropy increases, disorder rises, and yet patterns emerge
#
####
set -euo pipefail

# modules/create-organizations.sh
# Loads config from config.env and creates multiple organizations with varied settings

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
ORG_PREFIX="chaos-org"

echo "Creating $NUM_ORGS organizations..."

# Organization visibility options
VISIBILITIES=("public" "internal" "private")

for i in $(seq 1 "$NUM_ORGS"); do
  ORG_NAME="${ORG_PREFIX}-${TS}-${i}"
  # Rotate through visibility options
  VISIBILITY=${VISIBILITIES[$(( (i-1) % ${#VISIBILITIES[@]} ))]}
  
  echo "   • Creating organization $i/$NUM_ORGS: $ORG_NAME (${VISIBILITY})"
  
  # Create organization with varied settings
  RESP=$(curl -k -s -X POST -H "$AUTH" "$API/admin/organizations" \
    -d "{
      \"login\":\"${ORG_NAME}\",
      \"admin\":\"${ADMIN_USERNAME:-admin}\",
      \"profile_name\":\"Chaos Engine Org ${i}\",
      \"billing_email\":\"${BILLING_EMAIL:-admin@example.com}\",
      \"company\":\"Chaos Engine Testing Suite\",
      \"default_repository_permission\":\"read\"
    }")
  
  ORG_ID=$(echo "$RESP" | jq -r '.id // empty')
  if [[ -z "$ORG_ID" ]]; then
    echo "     ⚠ Failed to create organization: $(echo "$RESP" | jq -r '.message // "Unknown error"')"
    continue
  fi
  
  echo "     → Created organization ID: $ORG_ID"
  
  # Customize organization settings
  echo "     → Configuring organization settings"
  curl -k -s -X PATCH -H "$AUTH" "$API/orgs/${ORG_NAME}" \
    -d "{
      \"name\":\"Chaos Engine Org ${i}\",
      \"description\":\"Test organization ${i} created by Chaos Engine\",
      \"default_repository_permission\":\"read\",
      \"members_can_create_repositories\":true,
      \"members_can_create_public_repositories\":$(( i % 2 )),
      \"members_can_create_private_repositories\":true,
      \"members_can_create_internal_repositories\":$(( (i+1) % 2 ))
    }" >/dev/null
  
  # Create a few organization webhooks with different events
  WEBHOOK_EVENTS=(
    "\"push\",\"pull_request\""
    "\"issues\",\"issue_comment\",\"pull_request_review\""
    "\"repository\",\"workflow_job\",\"workflow_run\""
  )
  
  # Create 1-3 webhooks per org depending on org number
  NUM_HOOKS=$(( (i % 3) + 1 ))
  for j in $(seq 1 "$NUM_HOOKS"); do
    EVENT_SET=${WEBHOOK_EVENTS[$(( (j-1) % ${#WEBHOOK_EVENTS[@]} ))]}
    echo "     → Creating webhook $j with events: $EVENT_SET"
    
    HOOK_ID=$(curl -k -s -X POST -H "$AUTH" "$API/orgs/${ORG_NAME}/hooks" \
      -d "{
        \"name\":\"web\",
        \"active\":true,
        \"events\":[${EVENT_SET}],
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
  done
  
  echo "     ✓ Organization setup complete"
  sleep 2
done

echo "✅ create-organizations module complete!"
echo "Created $NUM_ORGS organizations with prefixes: ${ORG_PREFIX}-${TS}-*"
