
#!/bin/bash

# Configuration - Set these variables
# Default values that can be overridden by environment variables
: "${GITHUB_PAT:=your-personal-access-token}"
: "${GITHUB_ENV:=GHES}"  # Options: "GHES" or "GHEC"
: "${GITHUB_HOSTNAME:=your-github-enterprise-server.com}"  # e.g., github.example.com

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pat=*) GITHUB_PAT="${1#*=}" ;;
    --env=*) GITHUB_ENV="${1#*=}" ;;
    --hostname=*) GITHUB_HOSTNAME="${1#*=}" ;;
    --help) 
      echo "Usage: $0 [--pat=TOKEN] [--env=GHES|GHEC] [--hostname=hostname]" 
      echo "Or use environment variables: GITHUB_PAT, GITHUB_ENV, GITHUB_HOSTNAME"
      exit 0
      ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# Validate parameters
if [[ "$GITHUB_PAT" == "your-personal-access-token" ]]; then
    echo "Error: Personal Access Token not specified"
    echo "Set GITHUB_PAT environment variable or use --pat=TOKEN"
    exit 1
fi

if [[ "$GITHUB_ENV" == "GHEC" ]]; then
    API_BASE="https://api.github.com"
    echo "Using GitHub Enterprise Cloud (GHEC) environment"
else
    if [[ "$GITHUB_HOSTNAME" == "your-github-enterprise-server.com" ]]; then
        echo "Error: GitHub Enterprise Server hostname not specified"
        echo "Set GITHUB_HOSTNAME environment variable or use --hostname=HOSTNAME"
        exit 1
    fi
    API_BASE="https://${GITHUB_HOSTNAME}/api/v3"
    echo "Using GitHub Enterprise Server (GHES) environment at $GITHUB_HOSTNAME"
fi

# Function to make API calls
function github_api_get {
    local response
    response=$(curl -s -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}$1")
    
    # Check for API rate limiting
    if [[ "$response" == *"API rate limit exceeded"* ]]; then
        echo "Error: GitHub API rate limit exceeded. Please try again later." >&2
    fi
    
    # Check for auth issues
    if [[ "$response" == *"Bad credentials"* ]]; then
        echo "Error: Authentication failed. Check your Personal Access Token." >&2
    fi
    
    echo "$response"
}

# Function to get page count from Link header
function get_last_page {
    local header="$1"
    local last_page=1
    
    if [[ $header =~ .*\<.*page=([0-9]+).*\>.*rel=\"last\".* ]]; then
        last_page="${BASH_REMATCH[1]}"
    fi
    
    echo $last_page
}

echo "Fetching organizations from GitHub Enterprise Server..."
echo "---------------------------------------------------------"

# Determine the API endpoint based on the environment
if [[ "$GITHUB_ENV" == "GHEC" ]]; then
    # For GHEC, we need to use the /user/orgs endpoint to get organizations the user has access to
    orgs_endpoint="/user/orgs"
else
    # For GHES, we can use the /organizations endpoint to get all organizations
    orgs_endpoint="/organizations"
fi

# Get first page of organizations
orgs_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}${orgs_endpoint}?per_page=100")

# Check if we got a valid response
if [[ -z "$orgs_response_headers" ]]; then
    echo "Error: Failed to connect to GitHub API. Check your hostname and network connection."
    exit 1
fi

orgs_last_page=$(get_last_page "$orgs_response_headers")
all_orgs=()

# Fetch all pages of organizations
for page in $(seq 1 $orgs_last_page); do
    echo "Fetching organizations page $page of $orgs_last_page..."
    orgs_page=$(github_api_get "${orgs_endpoint}?per_page=100&page=$page")
    
    # Check if response is valid JSON
    if ! echo "$orgs_page" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response from GitHub API."
        echo "Response: $orgs_page"
        echo "Please check your credentials and hostname."
        exit 1
    fi
    
    # Extract organization logins and add to array
    org_logins=$(echo "$orgs_page" | jq -r '.[].login')
    
    if [[ -z "$org_logins" ]]; then
        echo "No organizations found on page $page."
        continue
    fi
    
    while read -r org_login; do
        # Skip empty lines
        [[ -z "$org_login" ]] && continue
        all_orgs+=("$org_login")
    done <<< "$org_logins"
done

echo
echo "Found ${#all_orgs[@]} organizations."
echo

# Check if we found any organizations
if [[ ${#all_orgs[@]} -eq 0 ]]; then
    echo "No organizations found. Please check your credentials and permissions."
    exit 1
fi

# Set up temporary file handling
TEMP_DIR="/tmp"
TEMP_FILE_PREFIX="gh_teams_${USER}_$$"
TEAMS_TEMP_FILE="${TEMP_DIR}/${TEMP_FILE_PREFIX}_teams.json"

# Create a trap to clean up temporary files on exit
trap 'rm -f "${TEMP_DIR}/${TEMP_FILE_PREFIX}"*' EXIT

# Create a CSV file with the report
REPORT_FILE="team_report_$(date +%Y%m%d_%H%M%S).csv"
echo "Organization,Team Name,Privacy,Member Count,Members" > "$REPORT_FILE"

# Summary counters
total_teams=0
total_team_members=0

# For each organization, get teams and their details
for org in "${all_orgs[@]}"; do
    # Skip empty org names
    [[ -z "$org" ]] && continue
    
    echo "Processing organization: $org"
    
    # Get headers to check pagination for teams
    teams_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/teams?per_page=100")
    
    # Check if we got a valid response
    if [[ -z "$teams_response_headers" ]]; then
        echo "Error: Failed to get teams for organization: $org"
        continue
    fi
    
    teams_last_page=$(get_last_page "$teams_response_headers")
    
    org_team_count=0
    
    # Fetch all pages of teams for this org
    for page in $(seq 1 $teams_last_page); do
        teams_page=$(github_api_get "/orgs/${org}/teams?per_page=100&page=$page")
        
        # Check if response is valid JSON
        if ! echo "$teams_page" | jq empty 2>/dev/null; then
            echo "Warning: Invalid JSON response for teams in $org (page $page)"
            echo "Response: $teams_page"
            continue
        fi
        
        # Process each team - save to temporary file to avoid subshell issue
        team_data=$(echo "$teams_page" | jq -c '.[]')
        if [ -n "$team_data" ]; then
            echo "$team_data" > "$TEAMS_TEMP_FILE"
            
            # Count teams on this page
            team_count=$(echo "$team_data" | wc -l)
            org_team_count=$((org_team_count + team_count))
            
            # Process each team individually to avoid subshell issues
            while IFS= read -r team; do
                team_name=$(echo "$team" | jq -r '.name')
                team_slug=$(echo "$team" | jq -r '.slug')
                team_privacy=$(echo "$team" | jq -r '.privacy')
                
                echo "  - Team: $team_name (Privacy: $team_privacy)"
                
                # Get members for this team
                echo -n "    Fetching members for team: $team_name... "
                members_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/teams/${team_slug}/members?per_page=100")
                
                # Check if we got a valid response
                if [[ -z "$members_response_headers" ]]; then
                    echo "Error: Failed to get response from API for team: $team_name in org: $org"
                    team_member_count=0
                    team_members="ERROR"
                    continue
                fi
                
                members_last_page=$(get_last_page "$members_response_headers")
                
                team_member_count=0
                team_members=""
                
                # Fetch all pages of members for this team
                for member_page in $(seq 1 $members_last_page); do
                    members_page=$(github_api_get "/orgs/${org}/teams/${team_slug}/members?per_page=100&page=$member_page")
                    
                    # Check if response is valid JSON
                    if ! echo "$members_page" | jq empty 2>/dev/null; then
                        echo "Warning: Invalid JSON response for team $team_name in $org (page $member_page)"
                        continue
                    fi
                    
                    # Count members
                    page_member_count=$(echo "$members_page" | jq '. | length')
                    # Handle empty result
                    if [[ -z "$page_member_count" ]]; then
                        page_member_count=0
                    fi
                    
                    team_member_count=$((team_member_count + page_member_count))
                    
                    # Get member logins
                    page_members=$(echo "$members_page" | jq -r '.[].login' | tr '\n' ',' | sed 's/,$//')
                    if [ -n "$page_members" ]; then
                        if [ -n "$team_members" ]; then
                            team_members="${team_members},${page_members}"
                        else
                            team_members="${page_members}"
                        fi
                    fi
                done
                
                # Add to CSV report
                echo "\"$org\",\"$team_name\",\"$team_privacy\",\"$team_member_count\",\"$team_members\"" >> "$REPORT_FILE"
                
                # Update total members count - this will now work correctly
                total_team_members=$((total_team_members + team_member_count))
                echo "    Members: $team_member_count"
            done < "$TEAMS_TEMP_FILE"
            
            # We don't need to remove the temp file here as we're using a trap for cleanup
        else
            echo "  No teams found in organization: $org"
        fi
    done
    
    echo "  Total teams in $org: $org_team_count"
    total_teams=$((total_teams + org_team_count))
done

echo
echo "---------------------------------------------------------"
echo "Summary:"
echo "Total Organizations: ${#all_orgs[@]}"
echo "Total Teams: $total_teams"
echo "Total Team Memberships: $total_team_members"
echo "---------------------------------------------------------"
echo "Report saved to: $REPORT_FILE"

# Display the first few lines of the report for verification
if [[ -s "$REPORT_FILE" ]]; then
    echo
    echo "Report preview (first 5 rows):"
    echo "---------------------------------------------------------"
    head -n 5 "$REPORT_FILE"
    echo "---------------------------------------------------------"
fi

echo "Script completed successfully."
