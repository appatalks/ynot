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
ORG_NAMES=($(echo "$ORGS_JSON" | jq -r '.[].login'))

echo "Found ${#ORG_NAMES[@]} organization(s)."

# 2. Delete organizations (this will cascade delete all repos, teams, etc.)
for ORG_NAME in "${ORG_NAMES[@]}"; do
  echo "  • Deleting organization: ${ORG_NAME}"
  curl -k -s -X DELETE -H "$AUTH" "$API/admin/organizations/${ORG_NAME}"
  sleep 1
done

# 3. Get list of all users except the currently authenticated admin user
echo "Fetching users..."
USERS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/users?per_page=100")
USER_NAMES=($(echo "$USERS_JSON" | jq -r ".[] | select(.login != \"$ADMIN_CHECK\") | .login"))

echo "Found ${#USER_NAMES[@]} user(s) to delete."

# 4. Delete users
for USER_NAME in "${USER_NAMES[@]}"; do
  echo "  • Deleting user: ${USER_NAME}"
  # First, suspend the user (needed before deletion)
  curl -k -s -X PUT -H "$AUTH" "$API/users/${USER_NAME}/suspended"
  sleep 1
  # Then delete the user
  curl -k -s -X DELETE -H "$AUTH" "$API/admin/users/${USER_NAME}"
  sleep 1
done

# 5. Remove all broadcasts
echo "Removing all enterprise broadcasts..."
curl -k -s -X DELETE -H "$AUTH" "$API/enterprise/announcements"

# 6. Reset rate limits (if applicable)
echo "Resetting rate limits..."
curl -k -s -X DELETE -H "$AUTH" "$API/admin/rate_limits"

# 7. Clean up webhooks at enterprise level (if any)
echo "Cleaning up enterprise webhooks..."
HOOKS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/enterprise/hooks")
HOOK_IDS=($(echo "$HOOKS_JSON" | jq -r '.[].id'))

for HOOK_ID in "${HOOK_IDS[@]}"; do
  echo "  • Removing webhook ID: ${HOOK_ID}"
  curl -k -s -X DELETE -H "$AUTH" "$API/enterprise/hooks/${HOOK_ID}"
  sleep 1
done

echo -e "\n✅ GitHub Enterprise Server environment cleanup complete!"
echo "Your instance now contains only:"
echo "  • The license"
echo "  • The admin user account: ${ADMIN_CHECK}"
echo -e "\nYou can now run the build-enterprise.sh script to create a fresh test environment."
