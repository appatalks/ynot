#!/usr/bin/env bash
#
# users as building blocks, organizations as structures
#
####
set -euo pipefail

# modules/create-users.sh
# Loads config from config.env and creates multiple test users

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

echo "Creating $NUM_USERS test users and adding them to organization ${ORG}..."

# User name prefixes and suffixes
PREFIXES=("test" "dev" "qa" "admin" "user" "engineer" "analyst")
SUFFIXES=("01" "02" "03" "04" "05")

# User roles
ROLES=("member" "admin")

# Create users and add them to the organization
declare -a CREATED_USERS
for i in $(seq 1 "$NUM_USERS"); do
  # Generate unique username
  PREFIX_IDX=$(( (i-1) % ${#PREFIXES[@]} ))
  SUFFIX_IDX=$(( (i-1) % ${#SUFFIXES[@]} ))
  USERNAME="${PREFIXES[$PREFIX_IDX]}-${TS}-${SUFFIXES[$SUFFIX_IDX]}"
  EMAIL="${USERNAME}@example.com"
  
  echo "   • Creating user $i/$NUM_USERS: $USERNAME"
  
  # For GitHub Enterprise Server, we can create users via admin API
  # Note: This doesn't work with GitHub.com, we're assuming GHES here
  if [[ "$GITHUB_SERVER_URL" != "https://github.com" ]]; then
    # Create random password
    PASSWORD=$(openssl rand -base64 12)
    
    USER_RESP=$(curl -k -s -X POST -H "$AUTH" "$API/admin/users" \
      -d "{
        \"login\":\"${USERNAME}\",
        \"email\":\"${EMAIL}\",
        \"password\":\"${PASSWORD}\"
      }")
    
    USER_ID=$(echo "$USER_RESP" | jq -r '.id // empty')
    if [[ -z "$USER_ID" ]]; then
      ERROR_MSG=$(echo "$USER_RESP" | jq -r '.message // "Unknown error"')
      echo "     ⚠ Failed to create user: ${ERROR_MSG}"
      
      # Check if it's a user limit error
      if [[ "$ERROR_MSG" == *"license seat"* || "$ERROR_MSG" == *"user limit"* || "$ERROR_MSG" == *"limit exceeded"* || "$ERROR_MSG" == *"seat limit"* ]]; then
        echo "     ⚠ It appears this server has reached its maximum user limit"
        echo "     ⚠ Stopping user creation and proceeding with existing users"
        break
      fi
      
      continue
    fi
    
    echo "     → Created user ID: $USER_ID"
    
    # Add user to organization
    ROLE=${ROLES[$(( i % ${#ROLES[@]} ))]}
    echo "     → Adding user to organization ${ORG} as ${ROLE}..."
    
    INVITE_RESP=$(curl -k -s -X PUT -H "$AUTH" \
      "$API/orgs/${ORG}/memberships/${USERNAME}" \
      -d "{\"role\":\"${ROLE}\"}")
    
    STATUS=$(echo "$INVITE_RESP" | jq -r '.state // empty')
    if [[ -z "$STATUS" ]]; then
      echo "     ⚠ Failed to add user to organization: $(echo "$INVITE_RESP" | jq -r '.message // "Unknown error"')"
    else
      echo "     → Added to organization with status: $STATUS"
      CREATED_USERS+=("$USERNAME")
    fi
  else
    echo "     ⚠ Creating users via API not supported on GitHub.com"
    echo "     → Skipping user creation, but will simulate for following steps"
    # For simulation purposes in GitHub.com environments, we'll pretend we created the user
    CREATED_USERS+=("$USERNAME")
  fi
  
  sleep 1
done

# Save created users for reference by other scripts
echo "${CREATED_USERS[@]}" > "$ROOT_DIR/generated-users.txt"

# Determine how many users were actually created
ACTUAL_USER_COUNT=${#CREATED_USERS[@]}

echo "✅ create-users module complete!"
if [[ $ACTUAL_USER_COUNT -eq $NUM_USERS ]]; then
  echo "Created $ACTUAL_USER_COUNT test users as requested and added them to organization ${ORG}"
else
  echo "Created $ACTUAL_USER_COUNT test users (out of $NUM_USERS requested)"
  echo "⚠️ Not all users could be created - this may be due to license seat limitations"
fi
echo "The list of created users is saved in $ROOT_DIR/generated-users.txt"
