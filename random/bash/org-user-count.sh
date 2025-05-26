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
echo "Organization Membership Counts:"
echo "---------------------------------------------------------"
printf "%-40s | %s\n" "Organization" "Member Count"
echo "---------------------------------------------------------"

# For each organization, get member count
for org in "${all_orgs[@]}"; do
    # Get headers to check pagination for members
    members_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/members?per_page=100")
    members_last_page=$(get_last_page "$members_response_headers")
    
    total_members=0
    
    # Fetch all pages of members for this org
    for page in $(seq 1 $members_last_page); do
        members_page=$(github_api_get "/orgs/${org}/members?per_page=100&page=$page")
        page_count=$(echo "$members_page" | jq '. | length')
        total_members=$((total_members + page_count))
    done
    
    # Print the organization and member count
    printf "%-40s | %d\n" "$org" "$total_members"
done

echo "---------------------------------------------------------"
echo "Script completed successfully."
