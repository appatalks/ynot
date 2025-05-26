#!/usr/bin/env bash
#
# teams are nexus points where collaboration and conflict both live
#
####
set -euo pipefail

# modules/create-teams.sh
# Loads config from config.env and creates teams with varied settings

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

echo "Creating $NUM_TEAMS teams in organization ${ORG}..."

# Team name templates
TEAM_PREFIXES=("frontend" "backend" "devops" "security" "qa" "docs" "design" "product")
TEAM_TEMPLATES=(
  "%s-team"
  "%s-guild"
  "%s-squad"
  "%s-center"
)

# Team privacy options
PRIVACY_OPTIONS=("closed" "secret")

# Team permission options
# GitHub API only accepts pull, push, admin for repository permissions
# maintain and triage are not valid for team creation
PERMISSION_OPTIONS=("pull" "push" "admin")

# Load list of users from generated-users.txt if it exists
USERS=()
if [[ -f "$ROOT_DIR/generated-users.txt" ]]; then
  mapfile -t USERS < "$ROOT_DIR/generated-users.txt"
  echo "Loaded ${#USERS[@]} users from generated-users.txt"
  
  # If we have no users at all, teams won't be very useful
  if [[ ${#USERS[@]} -eq 0 ]]; then
    echo "⚠ No users available for teams. Consider running the create-users module first."
    echo "Continuing with team creation, but teams will have no members."
  fi
  
  # If the server has user limits, we may want to reduce the number of teams
  if [[ ${#USERS[@]} -lt 5 && $NUM_TEAMS -gt 5 ]]; then
    echo "⚠ Limited users detected ($NUM_USERS). Consider reducing NUM_TEAMS in config.env"
    echo "Creating teams with limited membership may result in less useful testing."
  fi
fi

# Get list of repositories in the organization
echo "Fetching repository list..."
REPOS_JSON=$(curl -k -s -X GET -H "$AUTH" "$API/orgs/${ORG}/repos?per_page=100")
REPO_NAMES=($(echo "$REPOS_JSON" | jq -r '.[].name'))

if [[ ${#REPO_NAMES[@]} -eq 0 ]]; then
  echo "No repositories found in organization ${ORG}"
else
  echo "Found ${#REPO_NAMES[@]} repositories"
fi

# Create teams with varied settings
for i in $(seq 1 "$NUM_TEAMS"); do
  # Generate team name
  PREFIX_IDX=$(( (i-1) % ${#TEAM_PREFIXES[@]} ))
  TEMPLATE_IDX=$(( (i-1) % ${#TEAM_TEMPLATES[@]} ))
  PREFIX="${TEAM_PREFIXES[$PREFIX_IDX]}"
  TEMPLATE="${TEAM_TEMPLATES[$TEMPLATE_IDX]}"
  # Ensure team name only contains alphanumeric characters, hyphens, and underscores
  TEAM_NAME=$(printf "$TEMPLATE" "$PREFIX")-"${TS:(-4)}"
  # Remove any invalid characters
  TEAM_NAME=$(echo "$TEAM_NAME" | tr -cd 'a-zA-Z0-9-_')
  
  # Set privacy and permission
  PRIVACY=${PRIVACY_OPTIONS[$(( i % ${#PRIVACY_OPTIONS[@]} ))]}
  PERMISSION=${PERMISSION_OPTIONS[$(( (i+2) % ${#PERMISSION_OPTIONS[@]} ))]}
  
  echo "   • Creating team $i/$NUM_TEAMS: $TEAM_NAME ($PRIVACY, $PERMISSION)"
  
  # Create the team
  TEAM_RESP=$(curl -k -s -X POST -H "$AUTH" "$API/orgs/${ORG}/teams" \
    -d "{
      \"name\":\"${TEAM_NAME}\",
      \"description\":\"${TEAM_NAME} - created by Chaos Engine\",
      \"privacy\":\"${PRIVACY}\",
      \"permission\":\"${PERMISSION}\",
      \"repo_names\":[]
    }")
  
  TEAM_ID=$(echo "$TEAM_RESP" | jq -r '.id // empty')
  if [[ -z "$TEAM_ID" ]]; then
    echo "     ⚠ Failed to create team: $(echo "$TEAM_RESP" | jq -r '.message // "Unknown error"')"
    continue
  fi
  
  TEAM_SLUG=$(echo "$TEAM_RESP" | jq -r '.slug // empty')
  echo "     → Created team ID: $TEAM_ID, slug: $TEAM_SLUG"
  
  # Create child teams for some teams (creating a hierarchy)
  if [[ $(( i % 3 )) -eq 0 && i -lt $(( NUM_TEAMS - 1 )) ]]; then
    echo "     → Creating child teams..."
    
    for j in $(seq 1 2); # Create 2 child teams
      do
        CHILD_NAME="${TEAM_NAME}-sub${j}"
        # Remove any invalid characters from child team name
        CHILD_NAME=$(echo "$CHILD_NAME" | tr -cd 'a-zA-Z0-9-_')
        CHILD_PRIVACY=${PRIVACY_OPTIONS[$(( (i+j) % ${#PRIVACY_OPTIONS[@]} ))]}
        
        echo "       • Creating child team: $CHILD_NAME"
        # Use a valid permission for child teams
        CHILD_PERMISSION=${PERMISSION_OPTIONS[$(( (i+j) % ${#PERMISSION_OPTIONS[@]} ))]}
        
        CHILD_RESP=$(curl -k -s -X POST -H "$AUTH" "$API/orgs/${ORG}/teams" \
          -d "{
            \"name\":\"${CHILD_NAME}\",
            \"description\":\"Child team ${j} of ${TEAM_NAME}\",
            \"privacy\":\"${CHILD_PRIVACY}\",
            \"permission\":\"${CHILD_PERMISSION}\",
            \"parent_team_id\":${TEAM_ID}
          }")
        
        CHILD_ID=$(echo "$CHILD_RESP" | jq -r '.id // empty')
        CHILD_SLUG=$(echo "$CHILD_RESP" | jq -r '.slug // empty')
        if [[ -n "$CHILD_ID" ]]; then
          echo "       → Created child team ID: $CHILD_ID, slug: $CHILD_SLUG"
        else
          echo "       ⚠ Failed to create child team: $(echo "$CHILD_RESP" | jq -r '.message // "Unknown error"')"
        fi
      done
  fi
  
  # Add users to team
  if [[ ${#USERS[@]} -gt 0 ]]; then
    # Determine how many users to add to this team (1-5)
    NUM_USERS_TO_ADD=$(( (i % 5) + 1 ))
    # Ensure we don't try to add more users than we have
    NUM_USERS_TO_ADD=$(( NUM_USERS_TO_ADD > ${#USERS[@]} ? ${#USERS[@]} : NUM_USERS_TO_ADD ))
    
    echo "     → Adding $NUM_USERS_TO_ADD users to team..."
    
    # If we have very few users, distribute them carefully to avoid overloading
    if [[ ${#USERS[@]} -lt 3 && $i -gt 2 ]]; then
      # For later teams with limited users, reduce the number to prevent conflicts
      NUM_USERS_TO_ADD=1
      echo "     → Limited user pool detected, reducing to $NUM_USERS_TO_ADD user per team"
    fi
    
    for j in $(seq 1 "$NUM_USERS_TO_ADD"); do
      # Select user in a round-robin fashion
      USER_IDX=$(( (i + j - 2) % ${#USERS[@]} ))
      USER="${USERS[$USER_IDX]}"
      
      # Determine role (maintainer is less common than member)
      ROLE="member"
      if [[ $(( (i + j) % 5 )) -eq 0 ]]; then
        ROLE="maintainer"
      fi
      
      echo "       • Adding $USER as $ROLE"
      
      ADD_RESP=$(curl -k -s -X PUT -H "$AUTH" \
        "$API/orgs/${ORG}/teams/${TEAM_SLUG}/memberships/${USER}" \
        -d "{\"role\":\"${ROLE}\"}")
      
      # Check if there was an error
      ERROR_MSG=$(echo "$ADD_RESP" | jq -r '.message // empty')
      if [[ -n "$ERROR_MSG" ]]; then
        echo "       ⚠ Failed to add user to team: $ERROR_MSG"
        
        # If we've hit a rate limit or resource limit, pause before continuing
        if [[ "$ERROR_MSG" == *"rate limit"* || "$ERROR_MSG" == *"abuse"* ]]; then
          echo "       ⚠ Rate limiting detected, pausing for 30 seconds"
          sleep 30
        fi
      fi
    done
  else
    echo "     → No users available to add to team"
  fi
  
  # Assign repositories to the team if available
  if [[ ${#REPO_NAMES[@]} -gt 0 ]]; then
    # Determine how many repos to add to this team (1-3)
    NUM_REPOS_TO_ADD=$(( (i % 3) + 1 ))
    # Ensure we don't try to add more repos than we have
    NUM_REPOS_TO_ADD=$(( NUM_REPOS_TO_ADD > ${#REPO_NAMES[@]} ? ${#REPO_NAMES[@]} : NUM_REPOS_TO_ADD ))
    
    echo "     → Adding $NUM_REPOS_TO_ADD repositories to team..."
    
    for j in $(seq 1 "$NUM_REPOS_TO_ADD"); do
      # Select repo in a round-robin fashion
      REPO_IDX=$(( (i + j - 2) % ${#REPO_NAMES[@]} ))
      REPO="${REPO_NAMES[$REPO_IDX]}"
      
      # Vary the permissions for repos within teams
      # For repository permissions, we can use pull, push, admin, maintain, triage
      REPO_PERMISSIONS=("pull" "push" "admin" "maintain" "triage")  
      REPO_PERMISSION=${REPO_PERMISSIONS[$(( (i + j) % ${#REPO_PERMISSIONS[@]} ))]}
      
      echo "       • Adding $REPO with $REPO_PERMISSION permission"
      
      curl -k -s -X PUT -H "$AUTH" \
        "$API/orgs/${ORG}/teams/${TEAM_SLUG}/repos/${ORG}/${REPO}" \
        -d "{\"permission\":\"${REPO_PERMISSION}\"}" >/dev/null
    done
  else
    echo "     → No repositories available to add to team"
  fi
  
  # Create team discussion for some teams
  if [[ $(( i % 2 )) -eq 0 ]]; then
    echo "     → Creating team discussions..."
    
    # Create team discussion with a pinned announcement
    DISC_RESP=$(curl -k -s -X POST -H "$AUTH" -H "Accept: application/vnd.github.echo-preview+json" \
      "$API/teams/${TEAM_ID}/discussions" \
      -d "{
        \"title\":\"Welcome to ${TEAM_NAME}\",
        \"body\":\"## Team Announcement\\n\\nWelcome to the ${TEAM_NAME} team! This is a pinned discussion with important team information.\\n\\n- Team lead: Team Lead Name\\n- Team goals: Build awesome things\\n- Meeting schedule: Every Monday at 10:00 AM\\n\\nPlease introduce yourself in the comments!\",
        \"private\":true,
        \"pinned\":true
      }")
    
    DISC_ID=$(echo "$DISC_RESP" | jq -r '.id // empty')
    if [[ -n "$DISC_ID" ]]; then
      echo "       → Created pinned discussion"
      
      # Add a comment to the discussion
      curl -k -s -X POST -H "$AUTH" -H "Accept: application/vnd.github.echo-preview+json" \
        "$API/teams/${TEAM_ID}/discussions/${DISC_ID}/comments" \
        -d "{
          \"body\":\"I'm excited to be part of this team! Looking forward to working with everyone.\"
        }" >/dev/null
    fi
    
    # Create additional regular discussion
    curl -k -s -X POST -H "$AUTH" -H "Accept: application/vnd.github.echo-preview+json" \
      "$API/teams/${TEAM_ID}/discussions" \
      -d "{
        \"title\":\"Current Sprint Goals\",
        \"body\":\"Let's discuss our current sprint goals and priorities for this week.\\n\\n1. Complete feature X\\n2. Fix critical bugs\\n3. Review documentation\\n\\nWhat's everyone working on?\",
        \"private\":true
      }" >/dev/null
  fi
  
  echo "     ✓ Team setup complete"
  sleep 2
done

echo "✅ create-teams module complete!"
echo "Created $NUM_TEAMS teams in organization ${ORG}"
