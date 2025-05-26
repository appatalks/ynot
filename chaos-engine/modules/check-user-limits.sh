#!/usr/bin/env bash
#
# count before adding, measure before cutting
#
####
set -euo pipefail

# modules/check-user-limits.sh
# Checks how many users already exist in the GitHub instance

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

AUTH="Authorization: token ${GITHUB_TOKEN}"

# Check if we can access the admin/users endpoint (enterprise admin only)
echo "Checking GitHub instance user limits..."

if [[ "$GITHUB_SERVER_URL" != "https://github.com" ]]; then
  # For GitHub Enterprise Server, we can check user limits
  USER_COUNT_RESP=$(curl -k -s -X GET -H "$AUTH" "$API/admin/stats/users" || echo '{"error": "No access to admin APIs"}')
  
  if echo "$USER_COUNT_RESP" | jq -e '.error' > /dev/null; then
    echo "⚠️ Unable to access user statistics API. You may need enterprise admin permissions."
    echo "Proceeding without user limit information."
  else
    TOTAL_USERS=$(echo "$USER_COUNT_RESP" | jq -r '.total // "Unknown"')
    SUSPENDED_USERS=$(echo "$USER_COUNT_RESP" | jq -r '.suspended // "0"')
    ACTIVE_USERS=$(echo "$USER_COUNT_RESP" | jq -r '.active // "Unknown"')
    
    echo "GitHub Instance User Statistics:"
    echo "--------------------------------"
    echo "Total Users:     $TOTAL_USERS"
    echo "Active Users:    $ACTIVE_USERS"
    echo "Suspended Users: $SUSPENDED_USERS"
    
    # Try to get license information
    LICENSE_INFO=$(curl -k -s -X GET -H "$AUTH" "$API/enterprise/settings/license" 2>/dev/null || echo '{"error": "No access to license API"}')
    
    if ! echo "$LICENSE_INFO" | jq -e '.error' > /dev/null; then
      SEATS=$(echo "$LICENSE_INFO" | jq -r '.seats // "Unknown"')
      SEATS_USED=$(echo "$LICENSE_INFO" | jq -r '.seats_used // "Unknown"')
      SEATS_AVAILABLE=$(( SEATS - SEATS_USED ))
      
      echo "License Seats:   $SEATS"
      echo "Seats Used:      $SEATS_USED"
      echo "Seats Available: $SEATS_AVAILABLE"
      
      if [[ "$SEATS_AVAILABLE" -lt "$NUM_USERS" ]]; then
        echo
        echo "⚠️  Warning: You're attempting to create $NUM_USERS users, but only $SEATS_AVAILABLE license seats are available."
        echo "    Consider reducing NUM_USERS in config.env to $SEATS_AVAILABLE or fewer."
        
        # Automatically adjust NUM_USERS if requested
        if [[ "${AUTO_ADJUST_NUM_USERS:-false}" == "true" ]]; then
          if [[ "$SEATS_AVAILABLE" -gt 0 ]]; then
            echo "    Auto-adjusting NUM_USERS from $NUM_USERS to $SEATS_AVAILABLE"
            sed -i "s/^export NUM_USERS=.*$/export NUM_USERS=$SEATS_AVAILABLE  # Auto-adjusted due to license limits/" "$ROOT_DIR/config.env"
          else
            echo "    ⚠️ No seats available. Setting NUM_USERS to 0."
            sed -i "s/^export NUM_USERS=.*$/export NUM_USERS=0  # Auto-adjusted due to license limits/" "$ROOT_DIR/config.env"
          fi
        fi
      fi
    else
      echo "License information not available."
    fi
  fi
else
  echo "Running on GitHub.com - user creation requires manual invitation."
  echo "The script will simulate user creation for GitHub.com."
fi

echo
echo "✅ check-user-limits module complete!"
