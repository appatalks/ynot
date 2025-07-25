#!/usr/bin/env bash
#
# entropy increases, disorder rises, and yet patterns emerge
#
####
set -euo pipefail

# modules/create-organizations.sh
# Loads config from config.env and creates multiple organizations with varied settings

# Check for noninteractive mode
NONINTERACTIVE=false
if [[ $# -gt 0 && "${1:-}" == "--noninteractive" ]]; then
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

# Verify admin user and site admin privileges
echo "Verifying GitHub Enterprise admin access..."

# Check for API rate limit issues before starting
RATE_LIMIT_INFO=$(curl -k -s -X GET -H "$AUTH" "$API/rate_limit")
CORE_REMAINING=$(echo "$RATE_LIMIT_INFO" | jq -r '.resources.core.remaining // 5000')
CORE_RESET=$(echo "$RATE_LIMIT_INFO" | jq -r '.resources.core.reset // 0')
CORE_RESET_TIME=$(date -d "@$CORE_RESET" 2>/dev/null || date -r "$CORE_RESET" 2>/dev/null || echo "Unknown time")

echo "GitHub API rate limit status: $CORE_REMAINING requests remaining (resets at $CORE_RESET_TIME)"
if [[ "$CORE_REMAINING" -lt 100 ]]; then
  echo "⚠️ Warning: GitHub API rate limit is low ($CORE_REMAINING remaining)."
  echo "    Creating many organizations may fail due to rate limiting."
  echo "    Rate limit will reset at: $CORE_RESET_TIME"
  
  # If very close to limit, ask for confirmation
  if [[ "$CORE_REMAINING" -lt 20 ]]; then
    echo "⚠️ Rate limit critically low! Consider waiting until the rate limit resets."
    prompt_user "Do you want to continue anyway? (y/n) " "y"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborting organization creation. Try again after rate limit reset."
      exit 0
    fi
  fi
fi

ADMIN_CHECK=$(curl -k -s -X GET -H "$AUTH" "$API/user" | jq -r '.login // ""')

if [[ -z "$ADMIN_CHECK" ]]; then
  echo "⚠️ Failed to authenticate with GitHub API. Check your token."
  exit 1
fi

echo "Authenticated as: $ADMIN_CHECK"

# Check for site admin privileges by attempting multiple methods
echo "Checking site admin privileges..."

# Method 1: Check site_admin flag on user profile
USER_INFO=$(curl -k -s -X GET -H "$AUTH" "$API/user")
IS_SITE_ADMIN=$(echo "$USER_INFO" | jq -r '.site_admin // false')

# Method 2: Attempt to access admin endpoints
if [[ "$IS_SITE_ADMIN" != "true" ]]; then
  SITE_ADMIN_CHECK=$(curl -k -s -X GET -H "$AUTH" "$API/admin" 2>&1 || echo "Not a site admin")
  
  if [[ ! "$SITE_ADMIN_CHECK" == *"Not Found"* && ! "$SITE_ADMIN_CHECK" == *"Not a site admin"* ]]; then
    IS_SITE_ADMIN=true
  else
    IS_SITE_ADMIN=false
  fi
fi

# Report status
if [[ "$IS_SITE_ADMIN" == "true" ]]; then
  echo "✅ Authenticated user has site admin privileges."
else
  echo "⚠️ Warning: The authenticated user does not appear to have site admin privileges."
  echo "    Creating organizations requires site admin access on GitHub Enterprise Server."
  echo "    You may want to use a different token with site admin privileges."
  
  # Show current user's scopes for better diagnostic information
  echo -n "    Token scopes: "
  curl -k -s -I -X GET -H "$AUTH" "$API/user" | grep -i "x-oauth-scopes" || echo "Unable to determine token scopes"
  
  # Ask for confirmation to continue
  prompt_user "Do you want to continue anyway? (y/n) " "y"
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting organization creation."
    exit 1
  fi
fi

# Set admin username to the authenticated user if not explicitly provided
if [[ -z "${ADMIN_USERNAME:-}" ]]; then
  ADMIN_USERNAME="$ADMIN_CHECK"
  echo "Setting ADMIN_USERNAME to authenticated user: $ADMIN_USERNAME"
fi

# Verify that the admin user exists by checking user profile
if [[ "$ADMIN_USERNAME" != "$ADMIN_CHECK" ]]; then
  echo "Verifying that admin user '$ADMIN_USERNAME' exists..."
  ADMIN_USER_CHECK=$(curl -k -s -X GET -H "$AUTH" "$API/users/${ADMIN_USERNAME}" | jq -r '.login // ""')
  
  if [[ -z "$ADMIN_USER_CHECK" ]]; then
    echo "⚠️ Warning: The specified admin user '${ADMIN_USERNAME}' could not be found."
    echo "    Using the authenticated user ($ADMIN_CHECK) instead."
    ADMIN_USERNAME="$ADMIN_CHECK"
  else
    echo "✅ Admin user '$ADMIN_USERNAME' exists."
  fi
fi

echo "Creating $NUM_ORGS organizations..."

# Check if main ORG exists already
ORG_EXISTS=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG}" | jq -r '.login // empty')

# Organization visibility options
VISIBILITIES=("public" "internal" "private")

# Track created organizations
CREATED_ORGS=0

# If the main ORG exists, we'll only create additional organizations if explicitly requested
if [[ -n "$ORG_EXISTS" ]]; then
  echo "✅ Main organization ${ORG} already exists."
  # Count the existing org in our total
  CREATED_ORGS=$((CREATED_ORGS+1))
  
  # If NUM_ORGS is set to 1, we're done as the main org already exists
  if [[ "$NUM_ORGS" -eq 1 ]]; then
    echo "NUM_ORGS=1, no additional organizations needed."
    echo "✅ create-organizations module complete!"
    echo "Main organization ${ORG} already exists."
    exit 0
  fi
  
  # Otherwise, we'll create NUM_ORGS-1 additional organizations
  echo "Creating $((NUM_ORGS-1)) additional organizations..."
  for i in $(seq 2 "$NUM_ORGS"); do
    ORG_NAME="${ORG_PREFIX}-${TS}-${i}"
    # Rotate through visibility options
    VISIBILITY=${VISIBILITIES[$(( (i-1) % ${#VISIBILITIES[@]} ))]}
    
    echo "   • Creating organization $i/$NUM_ORGS: $ORG_NAME (${VISIBILITY})"
    
    # Create organization with varied settings
    echo "     → Using admin user: $ADMIN_USERNAME for organization creation"
    
    # Check if the right endpoint should be used based on the site admin status
    ENDPOINT="$API/admin/organizations"
    if [[ "$IS_SITE_ADMIN" == "false" ]]; then
      echo "     ⚠ Warning: Using non-admin organization creation endpoint"
      ENDPOINT="$API/orgs"
    fi
    
    ORG_DATA="{
        \"login\":\"${ORG_NAME}\",
        \"admin\":\"${ADMIN_USERNAME}\",
        \"profile_name\":\"Chaos Engine Org ${i}\",
        \"billing_email\":\"${BILLING_EMAIL:-admin@example.com}\",
        \"company\":\"Chaos Engine Testing Suite\",
        \"default_repository_permission\":\"read\"
      }"
    
    echo "     → API request data: $(echo "$ORG_DATA" | jq -c '.')"
    
    # Make the API request with full debug information
    RESP=$(curl -k -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
      -w "\n\nHTTP_STATUS:%{http_code}" \
      "$ENDPOINT" \
      -d "$ORG_DATA")
      
    # Extract HTTP status code
    HTTP_STATUS=$(echo "$RESP" | grep -o "HTTP_STATUS:[0-9]*" | cut -d':' -f2)
    # Extract the JSON response part
    JSON_RESP=$(echo "$RESP" | sed -n '/HTTP_STATUS/!p')
    
    echo "     → HTTP Status: $HTTP_STATUS"
    
    # Parse the organization ID from the response
    ORG_ID=$(echo "$JSON_RESP" | jq -r '.id // empty')
    
    # Check if the request was successful
    if [[ "$HTTP_STATUS" != "2"* || -z "$ORG_ID" ]]; then
      ERROR_MSG=$(echo "$JSON_RESP" | jq -r '.message // "Unknown error"')
      echo "     ⚠ Failed to create organization: $ERROR_MSG"
      
      # Debug: Show the full response for troubleshooting
      echo "     ⚠ HTTP Status Code: $HTTP_STATUS"
      echo "     ⚠ Full API response: $(echo "$JSON_RESP" | jq -c '.' 2>/dev/null || echo "$JSON_RESP")"
      
      # Check specific error cases
      if [[ "$ERROR_MSG" == *"Admin user could not be found"* || "$ERROR_MSG" == *"not found"* ]]; then
        echo "     ⚠ The specified admin user '${ADMIN_USERNAME}' does not exist in this GitHub instance."
        echo "     ⚠ Try using your own username or another existing admin user."
        
        # Offer to retry with the authenticated user
        if [[ "$ADMIN_USERNAME" != "$ADMIN_CHECK" ]]; then
          echo "     ℹ️ Would you like to retry with your authenticated username ($ADMIN_CHECK)? (y/n)"
          read -p "       " -n 1 -r
          echo
          if [[ $REPLY =~ ^[Yy]$ ]]; then
            ADMIN_USERNAME="$ADMIN_CHECK"
            echo "     ℹ️ Retrying with admin: $ADMIN_USERNAME"
            
            # Retry the organization creation with the current authenticated user
            echo "     → Retrying with admin user: $ADMIN_USERNAME"
            
            ORG_DATA="{
              \"login\":\"${ORG_NAME}\",
              \"admin\":\"${ADMIN_USERNAME}\",
              \"profile_name\":\"Chaos Engine Org ${i}\",
              \"billing_email\":\"${BILLING_EMAIL:-admin@example.com}\",
              \"company\":\"Chaos Engine Testing Suite\",
              \"default_repository_permission\":\"read\"
            }"
            
            # Make the API request with full debug information
            RESP=$(curl -k -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
              -w "\n\nHTTP_STATUS:%{http_code}" \
              "$ENDPOINT" \
              -d "$ORG_DATA")
              
            # Extract HTTP status code
            HTTP_STATUS=$(echo "$RESP" | grep -o "HTTP_STATUS:[0-9]*" | cut -d':' -f2)
            # Extract the JSON response part
            JSON_RESP=$(echo "$RESP" | sed -n '/HTTP_STATUS/!p')
            
            echo "     → HTTP Status: $HTTP_STATUS"
            ORG_ID=$(echo "$JSON_RESP" | jq -r '.id // empty')
            
            if [[ "$HTTP_STATUS" != "2"* || -z "$ORG_ID" ]]; then
              ERROR_MSG=$(echo "$JSON_RESP" | jq -r '.message // "Unknown error"')
              echo "     ⚠ Failed again: $ERROR_MSG"
              echo "     ⚠ Full API response: $(echo "$JSON_RESP" | jq -c '.' 2>/dev/null || echo "$JSON_RESP")"
              
              # Provide more specific guidance based on error
              if [[ "$HTTP_STATUS" == "404" ]]; then
                echo "     ⚠ API endpoint not found. Check if you're using GitHub Enterprise Server."
              elif [[ "$HTTP_STATUS" == "403" ]]; then
                echo "     ⚠ Permission denied. Check if the token has admin:org permissions."
              elif [[ "$HTTP_STATUS" == "401" ]]; then
                echo "     ⚠ Unauthorized. Check if the token is valid."
              fi
              continue
            else
              echo "     → Created organization ID: $ORG_ID"
              CREATED_ORGS=$((CREATED_ORGS+1))
            fi
          else
            continue
          fi
        else
          continue
        fi
      else
        continue
      fi
    else
      echo "     → Created organization ID: $ORG_ID"
      CREATED_ORGS=$((CREATED_ORGS+1))
    fi
    
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
else
  # The main ORG doesn't exist, so we'll create it plus any additional ones
  echo "Main organization ${ORG} doesn't exist. Will create it plus $((NUM_ORGS-1)) additional organizations."
  for i in $(seq 1 "$NUM_ORGS"); do
    if [[ $i -eq 1 ]]; then
      ORG_NAME="${ORG}"
    else
      ORG_NAME="${ORG_PREFIX}-${TS}-${i}"
    fi
    
    # Rotate through visibility options
    VISIBILITY=${VISIBILITIES[$(( (i-1) % ${#VISIBILITIES[@]} ))]}
    
    echo "   • Creating organization $i/$NUM_ORGS: $ORG_NAME (${VISIBILITY})"
    
    # Create organization with varied settings
    echo "     → Using admin user: $ADMIN_USERNAME for organization creation"
    
    # Check if the right endpoint should be used based on the site admin status
    ENDPOINT="$API/admin/organizations"
    if [[ "$IS_SITE_ADMIN" == "false" ]]; then
      echo "     ⚠ Warning: Using non-admin organization creation endpoint"
      ENDPOINT="$API/orgs"
    fi
    
    ORG_DATA="{
        \"login\":\"${ORG_NAME}\",
        \"admin\":\"${ADMIN_USERNAME}\",
        \"profile_name\":\"Chaos Engine Org ${i}\",
        \"billing_email\":\"${BILLING_EMAIL:-admin@example.com}\",
        \"company\":\"Chaos Engine Testing Suite\",
        \"default_repository_permission\":\"read\"
      }"
    
    echo "     → API request data: $(echo "$ORG_DATA" | jq -c '.')"
    
    # Make the API request with full debug information
    RESP=$(curl -k -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
      -w "\n\nHTTP_STATUS:%{http_code}" \
      "$ENDPOINT" \
      -d "$ORG_DATA")
      
    # Extract HTTP status code
    HTTP_STATUS=$(echo "$RESP" | grep -o "HTTP_STATUS:[0-9]*" | cut -d':' -f2)
    # Extract the JSON response part
    JSON_RESP=$(echo "$RESP" | sed -n '/HTTP_STATUS/!p')
    
    echo "     → HTTP Status: $HTTP_STATUS"
    
    # Parse the organization ID from the response
    ORG_ID=$(echo "$JSON_RESP" | jq -r '.id // empty')
    
    # Check if the request was successful
    if [[ "$HTTP_STATUS" != "2"* || -z "$ORG_ID" ]]; then
      ERROR_MSG=$(echo "$JSON_RESP" | jq -r '.message // "Unknown error"')
      echo "     ⚠ Failed to create organization: $ERROR_MSG"
      
      # Debug: Show the full response for troubleshooting
      echo "     ⚠ HTTP Status Code: $HTTP_STATUS"
      echo "     ⚠ Full API response: $(echo "$JSON_RESP" | jq -c '.' 2>/dev/null || echo "$JSON_RESP")"
      
      # Check specific error cases
      if [[ "$ERROR_MSG" == *"Admin user could not be found"* || "$ERROR_MSG" == *"not found"* ]]; then
        echo "     ⚠ The specified admin user '${ADMIN_USERNAME}' does not exist in this GitHub instance."
        echo "     ⚠ Try using your own username or another existing admin user."
        
        # Offer to retry with the authenticated user
        if [[ "$ADMIN_USERNAME" != "$ADMIN_CHECK" ]]; then
          echo "     ℹ️ Would you like to retry with your authenticated username ($ADMIN_CHECK)? (y/n)"
          read -p "       " -n 1 -r
          echo
          if [[ $REPLY =~ ^[Yy]$ ]]; then
            ADMIN_USERNAME="$ADMIN_CHECK"
            echo "     ℹ️ Retrying with admin: $ADMIN_USERNAME"
            
            # Retry the organization creation with the current authenticated user
            echo "     → Retrying with admin user: $ADMIN_USERNAME"
            
            ORG_DATA="{
              \"login\":\"${ORG_NAME}\",
              \"admin\":\"${ADMIN_USERNAME}\",
              \"profile_name\":\"Chaos Engine Org ${i}\",
              \"billing_email\":\"${BILLING_EMAIL:-admin@example.com}\",
              \"company\":\"Chaos Engine Testing Suite\",
              \"default_repository_permission\":\"read\"
            }"
            
            # Make the API request with full debug information
            RESP=$(curl -k -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
              -w "\n\nHTTP_STATUS:%{http_code}" \
              "$ENDPOINT" \
              -d "$ORG_DATA")
              
            # Extract HTTP status code
            HTTP_STATUS=$(echo "$RESP" | grep -o "HTTP_STATUS:[0-9]*" | cut -d':' -f2)
            # Extract the JSON response part
            JSON_RESP=$(echo "$RESP" | sed -n '/HTTP_STATUS/!p')
            
            echo "     → HTTP Status: $HTTP_STATUS"
            ORG_ID=$(echo "$JSON_RESP" | jq -r '.id // empty')
            
            if [[ "$HTTP_STATUS" != "2"* || -z "$ORG_ID" ]]; then
              ERROR_MSG=$(echo "$JSON_RESP" | jq -r '.message // "Unknown error"')
              echo "     ⚠ Failed again: $ERROR_MSG"
              echo "     ⚠ Full API response: $(echo "$JSON_RESP" | jq -c '.' 2>/dev/null || echo "$JSON_RESP")"
              
              # Provide more specific guidance based on error
              if [[ "$HTTP_STATUS" == "404" ]]; then
                echo "     ⚠ API endpoint not found. Check if you're using GitHub Enterprise Server."
              elif [[ "$HTTP_STATUS" == "403" ]]; then
                echo "     ⚠ Permission denied. Check if the token has admin:org permissions."
              elif [[ "$HTTP_STATUS" == "401" ]]; then
                echo "     ⚠ Unauthorized. Check if the token is valid."
              fi
              continue
            else
              echo "     → Created organization ID: $ORG_ID"
              CREATED_ORGS=$((CREATED_ORGS+1))
            fi
          else
            continue
          fi
        else
          continue
        fi
      else
        continue
      fi
    else
      echo "     → Created organization ID: $ORG_ID"
      CREATED_ORGS=$((CREATED_ORGS+1))
    fi
    
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
fi

# Display appropriate success or warning message based on actual results
if [[ $CREATED_ORGS -eq 0 ]]; then
  echo "❌ create-organizations module failed!"
  echo "No organizations were successfully created. Please check the following:"
  echo " - The admin user ($ADMIN_USERNAME) must exist on this GitHub instance"
  echo " - The authenticated user must have site admin privileges"
  echo " - The billing email must be valid"
  exit 1
elif [[ $CREATED_ORGS -lt $NUM_ORGS ]]; then
  echo "⚠️ create-organizations module partially complete."
  echo "Created $CREATED_ORGS out of $NUM_ORGS requested organizations with prefixes: ${ORG_PREFIX}-${TS}-*"
  
  # Print a list of the created organizations
  echo "Created organization names:"
  # If we're in the "main org exists" mode, we only created orgs from seq 2
  START_SEQ=$([[ -n "$ORG_EXISTS" ]] && echo "2" || echo "1")
  
  # List the main org first if it exists
  if [[ -n "$ORG_EXISTS" || $START_SEQ -eq 1 ]]; then
    echo " - ${ORG} (main org)"
  fi
  
  # Then list additional created organizations
  for i in $(seq $START_SEQ "$NUM_ORGS"); do
    ORG_NAME="${ORG_PREFIX}-${TS}-${i}"
    # Check if org exists by doing a HEAD request
    if curl -k -s -o /dev/null -w "%{http_code}" -X HEAD -H "$AUTH" "$API/orgs/${ORG_NAME}" | grep -q "20"; then
      echo " - $ORG_NAME"
    fi
  done
  
  # Exit with a warning code but not a failure
  exit 0
else
  # If the main org already existed and we're creating additional orgs, 
  # we need to account for it in our success message
  if [[ -n "$ORG_EXISTS" ]]; then
    TOTAL_ORGS=$((CREATED_ORGS + 1))
    echo "✅ create-organizations module complete!"
    echo "Main organization ${ORG} already existed + created $CREATED_ORGS additional organizations."
    echo "Total organizations: $TOTAL_ORGS"
  else
    echo "✅ create-organizations module complete!"
    echo "Created $CREATED_ORGS organizations with prefixes: ${ORG_PREFIX}-${TS}-*"
  fi
  
  # Print a list of the created organizations
  echo "Created organization names:"
  # If we're in the "main org exists" mode, 
  # we need to handle seq numbering differently
  START_SEQ=$([[ -n "$ORG_EXISTS" ]] && echo "2" || echo "1")
  
  # Always show the main org first
  echo " - ${ORG} (main organization)"
  
  # Then list additional created organizations
  for i in $(seq $START_SEQ "$NUM_ORGS"); do
    if curl -k -s -o /dev/null -w "%{http_code}" -X HEAD -H "$AUTH" "$API/orgs/${ORG_PREFIX}-${TS}-${i}" | grep -q "20"; then
      echo " - ${ORG_PREFIX}-${TS}-${i}"
    fi
  done
fi
