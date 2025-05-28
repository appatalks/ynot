#!/bin/bash
#
# Description: Lists all organizations and their member counts in either GHES or GHEC
#

# Configuration - Set these variables
# Default values that can be overridden by environment variables
: "${GITHUB_PAT:=ghp_****}"
: "${GITHUB_ENV:=GHES}"  # Options: "GHES" or "GHEC"
: "${GITHUB_HOSTNAME:=git.example.com}"  # e.g., github.example.com

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

#########################################################################

# Validate parameters
if [[ "$GITHUB_PAT" == "your-personal-access-token" ]]; then
    echo "Error: Personal Access Token not specified"
    echo "Set GITHUB_PAT environment variable or use --pat=TOKEN"
    exit 1
fi

if [[ "$GITHUB_ENV" != "GHES" && "$GITHUB_ENV" != "GHEC" ]]; then
    echo "Error: Invalid environment specified: $GITHUB_ENV"
    echo "Valid options are GHES or GHEC"
    exit 1
fi

if [[ "$GITHUB_ENV" == "GHES" && "$GITHUB_HOSTNAME" == "your-github-enterprise-server.com" ]]; then
    echo "Error: GitHub Enterprise Server hostname not specified"
    echo "Set GITHUB_HOSTNAME environment variable or use --hostname=HOSTNAME"
    exit 1
fi

# API Base URL (determined by environment)
if [[ "$GITHUB_ENV" == "GHEC" ]]; then
    API_BASE="https://api.github.com"
    echo "Using GitHub Enterprise Cloud (GHEC) environment"
else
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

echo "Fetching organizations..."
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
echo "Organization Membership Counts:"
echo "---------------------------------------------------------"
printf "%-40s | %s\n" "Organization" "Member Count"
echo "---------------------------------------------------------"

# Check if we found any organizations
if [[ ${#all_orgs[@]} -eq 0 ]]; then
    echo "No organizations found. Please check your credentials and permissions."
    exit 1
fi

# For each organization, get member count
for org in "${all_orgs[@]}"; do
    # Skip empty org names (should not happen with our improved checks)
    [[ -z "$org" ]] && continue

    echo -n "Processing org: $org... "
    
    # Get headers to check pagination for members
    members_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/members?per_page=100")
    
    # Check if we got a valid response
    if [[ -z "$members_response_headers" ]]; then
        echo "Error: Failed to get response from API for organization: $org"
        printf "%-40s | %s\n" "$org" "ERROR"
        continue
    fi
    
    members_last_page=$(get_last_page "$members_response_headers")
    
    total_members=0
    
    # Fetch all pages of members for this org
    for page in $(seq 1 $members_last_page); do
        members_page=$(github_api_get "/orgs/${org}/members?per_page=100&page=$page")
        
        # Check if response is valid JSON
        if ! echo "$members_page" | jq empty 2>/dev/null; then
            echo "Warning: Invalid JSON response for $org (page $page)"
            continue
        fi
        
        page_count=$(echo "$members_page" | jq '. | length')
        # Handle empty result
        if [[ -z "$page_count" ]]; then
            page_count=0
        fi
        
        total_members=$((total_members + page_count))
    done
    
    echo "Found $total_members members"
    
    # Print the organization and member count
    printf "%-40s | %d\n" "$org" "$total_members"
done

echo "---------------------------------------------------------"
echo "Script completed successfully."
