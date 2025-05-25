#!/usr/bin/env bash
#
# entropy can be reversed, but at what cost?
#
####
set -euo pipefail

# modules/clean-environment.sh
# Loads config from config.env and cleans up a GitHub Enterprise Server environment
# Keeping only the license and admin user

# Resolve directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load global configuration
source "$ROOT_DIR/config.env"

# Initialize error tracking arrays
SKIPPED_ORGS=()
SKIPPED_REPOS=()
SKIPPED_USERS=()
ERROR_MESSAGES=()

# Determine API endpoint
if [[ "$GITHUB_SERVER_URL" == "https://github.com" ]]; then
  echo "❌ This module is only compatible with GitHub Enterprise Server"
  echo "It should not be run against GitHub.com"
  exit 1
else
  API="${GITHUB_SERVER_URL%/}/api/v3"
fi

# Prepare identifiers
AUTH="Authorization: token ${GITHUB_TOKEN}"

# Verify admin user and site admin privileges
echo "Verifying GitHub Enterprise admin access..."
ADMIN_CHECK=$(curl -k -s -X GET -H "$AUTH" "$API/user" | jq -r '.login // ""')

if [[ -z "$ADMIN_CHECK" ]]; then
  echo "⚠️ Failed to authenticate with GitHub API. Check your token."
  exit 1
fi

echo "Authenticated as: $ADMIN_CHECK"

# Verify site admin privileges
USER_INFO=$(curl -k -s -X GET -H "$AUTH" "$API/user")
IS_SITE_ADMIN=$(echo "$USER_INFO" | jq -r '.site_admin // false')

if [[ "$IS_SITE_ADMIN" != "true" ]]; then
  echo "⚠️ This module requires site admin privileges."
  echo "The authenticated user does not appear to be a site administrator."
  exit 1
else
  echo "✅ Authenticated user has site admin privileges."
fi

# Ask for confirmation before proceeding
echo -e "\n⚠️  WARNING: This will delete ALL organizations, repositories, users, and other data"
echo "from this GitHub Enterprise Server instance, except for:"
echo "  • The license"
echo "  • The authenticated admin user account"
echo -e "\nThis operation is DESTRUCTIVE and CANNOT BE UNDONE."
read -p "Type 'CONFIRM-CLEANUP' to proceed: " CONFIRMATION

if [[ "$CONFIRMATION" != "CONFIRM-CLEANUP" ]]; then
  echo "Cleanup aborted."
  exit 1
fi

echo -e "\n🧹 Starting GitHub Enterprise Server cleanup...\n"

# 1. Get list of all organizations
echo "Fetching organizations..."
ORGS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/admin/organizations?per_page=100")
# Check if we got a valid response (array of orgs)
if echo "$ORGS_JSON" | jq -e 'type == "array"' > /dev/null; then
  ORG_NAMES=($(echo "$ORGS_JSON" | jq -r '.[].login'))
elif echo "$ORGS_JSON" | jq -e '.message == "Not Found"' > /dev/null; then
  # Try the regular orgs endpoint instead (don't show "not found" message as it's expected)
  ORGS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/organizations?per_page=100")
  if echo "$ORGS_JSON" | jq -e 'type == "array"' > /dev/null; then
    ORG_NAMES=($(echo "$ORGS_JSON" | jq -r '.[].login'))
  else
    echo "⚠️ Failed to fetch organizations."
    ERROR_MESSAGES+=("Failed to fetch organizations: $(echo "$ORGS_JSON" | jq -r '.message // "Unknown error"')")
    ORG_NAMES=()
  fi
else
  echo "⚠️ Failed to fetch organizations."
  ERROR_MESSAGES+=("Failed to fetch organizations: $(echo "$ORGS_JSON" | jq -r '.message // "Unknown error"')")
  ORG_NAMES=()
fi

echo "Found ${#ORG_NAMES[@]} organization(s)."

# 2. Delete organizations (this will cascade delete all repos, teams, etc.)
for ORG_NAME in "${ORG_NAMES[@]}"; do
  echo "  • Deleting organization: ${ORG_NAME}"
  
  # Check for special system organizations that should be skipped
  if [[ "$ORG_NAME" == "github" || "$ORG_NAME" == "actions" ]]; then
    echo "    ℹ️ Skipping system organization (expected to remain)"
    SKIPPED_ORGS+=("$ORG_NAME (system org)")
    continue
  fi
  
  # Try admin endpoint first
  DELETE_RESULT=$(curl -k -s -X DELETE -H "$AUTH" "$API/admin/organizations/${ORG_NAME}" -w "%{http_code}" -o /tmp/delete_output)
  HTTP_STATUS=$DELETE_RESULT
  
  # Check status code - if admin endpoint fails (404), try deleting via regular API
  if [[ "$HTTP_STATUS" == "404" ]]; then
    # Don't show "Admin deletion endpoint not found" as it's expected behavior
    
    # First check if current user is an owner of the organization
    MEMBERSHIP=$(curl -k -s -X GET -H "$AUTH" "$API/user/memberships/orgs/${ORG_NAME}")
    
    if echo "$MEMBERSHIP" | jq -e '.role == "admin"' > /dev/null; then
      # Method 1: Delete organization if user is an owner
      echo "    User is an owner, attempting to delete organization"
      DELETE_STATUS=$(curl -k -s -X DELETE -H "$AUTH" "$API/orgs/${ORG_NAME}" -w "%{http_code}" -o /dev/null)
      echo "$DELETE_STATUS"
    else
      # If not an owner, try to delete repositories one by one
      echo "    User is not an owner, attempting to delete repositories"
      REPOS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG_NAME}/repos?per_page=100")
      if echo "$REPOS_JSON" | jq -e 'type == "array"' > /dev/null; then
        REPO_NAMES=($(echo "$REPOS_JSON" | jq -r '.[].name'))
        echo "    Found ${#REPO_NAMES[@]} repositories to delete"
        FAILED_REPOS=0
        
        for REPO_NAME in "${REPO_NAMES[@]}"; do
          echo "      Deleting repository: ${ORG_NAME}/${REPO_NAME}"
          DELETE_REPO_RESULT=$(curl -k -s -X DELETE -H "$AUTH" "$API/repos/${ORG_NAME}/${REPO_NAME}" -w "%{http_code}" -o /tmp/delete_repo_output)
          
          if [[ "$DELETE_REPO_RESULT" != "2"* ]]; then
            FAILED_REPOS=$((FAILED_REPOS+1))
            ERROR_MSG=$(cat /tmp/delete_repo_output | jq -r '.message // "Unknown error"')
            SKIPPED_REPOS+=("${ORG_NAME}/${REPO_NAME} ($ERROR_MSG)")
          fi
          sleep 0.5
        done
        
        if [[ $FAILED_REPOS -gt 0 ]]; then
          echo "    ⚠️ Failed to delete $FAILED_REPOS repositories (see summary at end)"
          SKIPPED_ORGS+=("$ORG_NAME (has $FAILED_REPOS undeleted repos)")
        else
          echo "    ✓ All repositories deleted successfully"
        fi
      else
        echo "    ⚠️ Could not fetch repositories"
        SKIPPED_ORGS+=("$ORG_NAME (couldn't fetch repos)")
      fi
    fi
  elif [[ "$HTTP_STATUS" != "2"* ]]; then
    echo "    ⚠️ Failed to delete organization"
    ERROR_MSG=$(cat /tmp/delete_output | jq -r '.message // "Unknown error"')
    ERROR_MESSAGES+=("Failed to delete org $ORG_NAME: $ERROR_MSG")
    SKIPPED_ORGS+=("$ORG_NAME ($ERROR_MSG)")
  fi
  sleep 1
done

# 3. Get list of all users except the currently authenticated admin user
echo "Fetching users..."
USERS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/users?per_page=100")
# Check if we got a valid response (array of users)
if echo "$USERS_JSON" | jq -e 'type == "array"' > /dev/null; then
  USER_NAMES=($(echo "$USERS_JSON" | jq -r ".[] | select(.login != \"$ADMIN_CHECK\") | .login"))
elif echo "$USERS_JSON" | jq -e '.message' > /dev/null; then
  echo "⚠️ Failed to fetch users."
  ERROR_MESSAGES+=("Failed to fetch users: $(echo "$USERS_JSON" | jq -r '.message // "Unknown error"')")
  USER_NAMES=()
else
  echo "⚠️ Failed to fetch users."
  ERROR_MESSAGES+=("Failed to fetch users: Unknown error")
  USER_NAMES=()
fi

echo "Found ${#USER_NAMES[@]} user(s) to delete."

# 4. Delete users
for USER_NAME in "${USER_NAMES[@]}"; do
  echo "  • Deleting user: ${USER_NAME}"
  
  # Check if this appears to be a bot or system account (to avoid suspension attempts)
  if [[ "$USER_NAME" == *"[bot]"* || "$USER_NAME" == "ghost" || "$USER_NAME" == "github-enterprise" ]]; then
    echo "    ℹ️ Detected system or bot account, skipping suspension step"
    SKIPPED_USERS+=("$USER_NAME (system/bot account)")
    continue
  fi
  
  # First, suspend the user (needed before deletion)
  SUSPEND_RESULT=$(curl -k -s -X PUT -H "$AUTH" "$API/users/${USER_NAME}/suspended" -w "%{http_code}" -o /tmp/suspend_output)
  SUSPEND_STATUS=$SUSPEND_RESULT
  
  if [[ "$SUSPEND_STATUS" != "2"* ]]; then
    # Don't display detailed error messages for suspension failures
    echo "    ℹ️ User suspension skipped - proceeding to deletion"
    
    if echo "$(cat /tmp/suspend_output)" | jq -e '.message' > /dev/null; then
      ERROR_MSG=$(cat /tmp/suspend_output | jq -r '.message // "Unknown error"')
      if [[ "$ERROR_MSG" == "Organizations cannot be suspended."* ]]; then
        SKIPPED_USERS+=("$USER_NAME (organization account)")
        echo "    ℹ️ Skipping deletion for organization account"
        continue
      fi
    fi
  fi
  
  sleep 1
  
  # Then delete the user via admin endpoint
  DELETE_RESULT=$(curl -k -s -X DELETE -H "$AUTH" "$API/admin/users/${USER_NAME}" -w "%{http_code}" -o /tmp/delete_user_output)
  DELETE_STATUS=$DELETE_RESULT
  
  if [[ "$DELETE_STATUS" == "404" ]]; then
    # Try regular deletion endpoint if available, don't show "not found" message
    REGULAR_DELETE=$(curl -k -s -X DELETE -H "$AUTH" "$API/users/${USER_NAME}" -w "%{http_code}" -o /tmp/regular_delete_output)
    
    if [[ "$REGULAR_DELETE" != "2"* ]]; then
      echo "    ⚠️ Failed to delete user"
      ERROR_MSG=$(cat /tmp/regular_delete_output | jq -r '.message // "Unknown error"')
      SKIPPED_USERS+=("$USER_NAME ($ERROR_MSG)")
    fi
  elif [[ "$DELETE_STATUS" != "2"* ]]; then
    echo "    ⚠️ Failed to delete user"
    ERROR_MSG=$(cat /tmp/delete_user_output | jq -r '.message // "Unknown error"')
    SKIPPED_USERS+=("$USER_NAME ($ERROR_MSG)")
  fi
  
  sleep 1
done

# 5. Remove all broadcasts
echo "Removing all enterprise broadcasts..."
BROADCAST_RESULT=$(curl -k -s -X DELETE -H "$AUTH" "$API/enterprise/announcements" -w "%{http_code}" -o /tmp/broadcast_output)
BROADCAST_STATUS=$BROADCAST_RESULT

if [[ "$BROADCAST_STATUS" == "404" ]]; then
  # Don't show error for missing enterprise features, it's expected in some setups
  echo "ℹ️ Enterprise announcements feature not available"
elif [[ "$BROADCAST_STATUS" != "2"* ]]; then
  echo "⚠️ Failed to remove enterprise broadcasts"
  ERROR_MSG=$(cat /tmp/broadcast_output | jq -r '.message // "Unknown error"')
  ERROR_MESSAGES+=("Failed to remove broadcasts: $ERROR_MSG")
fi

# 6. Reset rate limits (if applicable)
echo "Resetting rate limits..."
RATE_LIMIT_RESULT=$(curl -k -s -X DELETE -H "$AUTH" "$API/admin/rate_limits" -w "%{http_code}" -o /tmp/rate_limit_output)
RATE_LIMIT_STATUS=$RATE_LIMIT_RESULT

if [[ "$RATE_LIMIT_STATUS" == "404" ]]; then
  # Don't show error for missing enterprise features, it's expected in some setups
  echo "ℹ️ Rate limit reset feature not available"
elif [[ "$RATE_LIMIT_STATUS" != "2"* ]]; then
  echo "⚠️ Failed to reset rate limits"
  ERROR_MSG=$(cat /tmp/rate_limit_output | jq -r '.message // "Unknown error"')
  ERROR_MESSAGES+=("Failed to reset rate limits: $ERROR_MSG")
fi

# 7. Clean up webhooks at enterprise level (if any)
echo "Cleaning up enterprise webhooks..."
HOOKS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/enterprise/hooks")

# Check if we got a valid response (array of hooks)
if echo "$HOOKS_JSON" | jq -e 'type == "array"' > /dev/null; then
  HOOK_IDS=($(echo "$HOOKS_JSON" | jq -r '.[].id'))
  echo "Found ${#HOOK_IDS[@]} enterprise webhook(s)."
  
  for HOOK_ID in "${HOOK_IDS[@]}"; do
    echo "  • Removing webhook ID: ${HOOK_ID}"
    DELETE_RESULT=$(curl -k -s -X DELETE -H "$AUTH" "$API/enterprise/hooks/${HOOK_ID}" -w "%{http_code}" -o /tmp/delete_hook_output)
    DELETE_STATUS=$DELETE_RESULT
    
    if [[ "$DELETE_STATUS" != "2"* ]]; then
      echo "    ⚠️ Failed to delete webhook"
      ERROR_MSG=$(cat /tmp/delete_hook_output | jq -r '.message // "Unknown error"')
      ERROR_MESSAGES+=("Failed to delete webhook $HOOK_ID: $ERROR_MSG")
    fi
    sleep 1
  done
elif echo "$HOOKS_JSON" | jq -e '.message == "Not Found"' > /dev/null; then
  # Don't show error for missing enterprise features, it's expected in some setups
  echo "ℹ️ Enterprise webhooks feature not available"
else
  echo "⚠️ Failed to fetch enterprise webhooks"
  ERROR_MSG=$(echo "$HOOKS_JSON" | jq -r '.message // "Unknown error"')
  ERROR_MESSAGES+=("Failed to fetch webhooks: $ERROR_MSG")
fi

# 8. Generate cleanup summary
ORGS_PROCESSED=${#ORG_NAMES[@]}
USERS_PROCESSED=${#USER_NAMES[@]}

echo -e "\n✅ GitHub Enterprise Server environment cleanup completed with the following results:"
echo "  • Organizations processed: $ORGS_PROCESSED"
echo "  • Users processed: $USERS_PROCESSED"
echo "  • Enterprise settings reset attempted"
echo -e "\nYour instance should now contain only:"
echo "  • The license"
echo "  • The admin user account: ${ADMIN_CHECK}"

# Check if we still have any organizations left (for verification)
REMAINING_ORGS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/organizations?per_page=100")
REMAINING_ORG_COUNT=$(echo "$REMAINING_ORGS_JSON" | jq -r 'length // 0')

echo -e "\nRemaining organization count: $REMAINING_ORG_COUNT"

if [[ "$REMAINING_ORG_COUNT" -gt 0 ]]; then
  # List up to 5 remaining orgs
  echo "Some organizations may still exist. Here are up to 5 remaining organizations:"
  echo "$REMAINING_ORGS_JSON" | jq -r '.[0:5] | .[] | "  • " + .login' 
  
  # Offer interactive mode for remaining orgs
  echo -e "\nWould you like to attempt deletion of these remaining organizations?"
  echo "This will use regular API endpoints for deletion (requires owner permissions)."
  read -p "Enter 'yes' to continue: " DELETE_REMAINING
  
  if [[ "$DELETE_REMAINING" == "yes" ]]; then
    echo "Attempting deletion of remaining organizations..."
    REMAINING_ORG_NAMES=($(echo "$REMAINING_ORGS_JSON" | jq -r '.[].login'))
    
    for ORG_NAME in "${REMAINING_ORG_NAMES[@]}"; do
      # Skip built-in orgs
      if [[ "$ORG_NAME" == "github" || "$ORG_NAME" == "actions" ]]; then
        echo "  • Skipping built-in organization: ${ORG_NAME}"
        continue
      fi
      
      echo "  • Attempting to delete: ${ORG_NAME}"
      MEMBERSHIP=$(curl -k -s -X GET -H "$AUTH" "$API/user/memberships/orgs/${ORG_NAME}")
      
      if echo "$MEMBERSHIP" | jq -e '.role == "admin"' > /dev/null; then
        curl -k -s -X DELETE -H "$AUTH" "$API/orgs/${ORG_NAME}"
        echo "    Organization deletion request sent"
      else
        echo "    ℹ️ Cannot delete - current user is not an owner of this organization"
      fi
      sleep 1
    done
  fi
fi

# 9. Display cleanup report with expected errors/skipped items
if [[ ${#SKIPPED_ORGS[@]} -gt 0 || ${#SKIPPED_REPOS[@]} -gt 0 || ${#SKIPPED_USERS[@]} -gt 0 || ${#ERROR_MESSAGES[@]} -gt 0 ]]; then
  echo -e "\n📋 Cleanup Report (expected limitations):"
  
  if [[ ${#SKIPPED_ORGS[@]} -gt 0 ]]; then
    echo -e "\n  Organizations skipped (${#SKIPPED_ORGS[@]}):"
    for ORG in "${SKIPPED_ORGS[@]}"; do
      echo "    • $ORG"
    done
  fi
  
  if [[ ${#SKIPPED_USERS[@]} -gt 0 ]]; then
    echo -e "\n  Users skipped (${#SKIPPED_USERS[@]}):"
    for USER in "${SKIPPED_USERS[@]}"; do
      echo "    • $USER"
    done
  fi
  
  if [[ ${#SKIPPED_REPOS[@]} -gt 0 ]]; then
    echo -e "\n  Some repositories could not be deleted (showing up to 10):"
    # Show at most 10 skipped repos to avoid overwhelming output
    for ((i=0; i<${#SKIPPED_REPOS[@]} && i<10; i++)); do
      echo "    • ${SKIPPED_REPOS[$i]}"
    done
    if [[ ${#SKIPPED_REPOS[@]} -gt 10 ]]; then
      REMAINING=$((${#SKIPPED_REPOS[@]} - 10))
      echo "    • ... and $REMAINING more"
    fi
  fi
  
  if [[ ${#ERROR_MESSAGES[@]} -gt 0 ]]; then
    echo -e "\n  Error messages:"
    for ERR in "${ERROR_MESSAGES[@]}"; do
      echo "    • $ERR"
    done
  fi
  
  echo -e "\nNOTE: Some errors are expected, especially for system organizations, built-in repositories, and bot accounts."
  echo "      These errors can be safely ignored if they relate to GitHub-managed resources."
fi

echo -e "\nYou can now run the build-enterprise.sh script to create a fresh test environment."
