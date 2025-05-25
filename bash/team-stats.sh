
#!/bin/bash

# Configuration - Set these variables
GITHUB_HOSTNAME="your-github-enterprise-server.com"  # e.g., github.example.com
GITHUB_PAT="your-personal-access-token"

# API Base URL
API_BASE="https://${GITHUB_HOSTNAME}/api/v3"

# Function to make API calls
function github_api_get {
    curl -s -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}$1"
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

# Get first page of organizations
orgs_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/organizations?per_page=100")
orgs_last_page=$(get_last_page "$orgs_response_headers")

all_orgs=()

# Fetch all pages of organizations
for page in $(seq 1 $orgs_last_page); do
    echo "Fetching organizations page $page of $orgs_last_page..."
    orgs_page=$(github_api_get "/organizations?per_page=100&page=$page")
    
    # Extract organization logins and add to array
    org_logins=$(echo "$orgs_page" | jq -r '.[].login')
    while read -r org_login; do
        all_orgs+=("$org_login")
    done <<< "$org_logins"
done

echo
echo "Found ${#all_orgs[@]} organizations."
echo

# Create a CSV file with the report
REPORT_FILE="team_report_$(date +%Y%m%d_%H%M%S).csv"
echo "Organization,Team Name,Privacy,Member Count,Members" > "$REPORT_FILE"

# Summary counters
total_teams=0
total_team_members=0

# For each organization, get teams and their details
for org in "${all_orgs[@]}"; do
    echo "Processing organization: $org"
    
    # Get headers to check pagination for teams
    teams_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/teams?per_page=100")
    teams_last_page=$(get_last_page "$teams_response_headers")
    
    org_team_count=0
    
    # Fetch all pages of teams for this org
    for page in $(seq 1 $teams_last_page); do
        teams_page=$(github_api_get "/orgs/${org}/teams?per_page=100&page=$page")
        
        # Process each team - save to temporary file to avoid subshell issue
        team_data=$(echo "$teams_page" | jq -c '.[]')
        if [ -n "$team_data" ]; then
            echo "$team_data" > teams_temp.json
            
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
                members_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/teams/${team_slug}/members?per_page=100")
                members_last_page=$(get_last_page "$members_response_headers")
                
                team_member_count=0
                team_members=""
                
                # Fetch all pages of members for this team
                for member_page in $(seq 1 $members_last_page); do
                    members_page=$(github_api_get "/orgs/${org}/teams/${team_slug}/members?per_page=100&page=$member_page")
                    
                    # Count members
                    page_member_count=$(echo "$members_page" | jq '. | length')
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
            done < teams_temp.json
            
            # Clean up temporary file
            rm -f teams_temp.json
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
echo "Script completed successfully."
