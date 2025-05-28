#!/bin/bash
# Description: Lists all GitHub Apps installed in all organizations for either GHES or GHEC

# Configuration - Set these variables
GITHUB_PAT="your-personal-access-token" 
GITHUB_ENV="GHES"  # Options: "GHES" or "GHEC"
GITHUB_HOSTNAME="your-github-enterprise-server.com"  # e.g., github.example.com

#########################################################################

# API Base URL (determined by environment)
if [[ "$GITHUB_ENV" == "GHEC" ]]; then
    API_BASE="https://api.github.com"
    echo "Using GitHub Enterprise Cloud (GHEC) environment"
else
    API_BASE="https://${GITHUB_HOSTNAME}/api/v3"
    echo "Using GitHub Enterprise Server (GHES) environment"
fi

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
    
    # Extract organization logins and add to array
    org_logins=$(echo "$orgs_page" | jq -r '.[].login')
    while read -r org_login; do
        all_orgs+=("$org_login")
    done <<< "$org_logins"
done

echo
echo "Found ${#all_orgs[@]} organizations."
echo
echo "Organization GitHub App Installations:"
echo "---------------------------------------------------------"
printf "%-30s | %-40s | %-15s | %s\n" "Organization" "App Name" "App ID" "Permissions"
echo "---------------------------------------------------------"

# For each organization, get installed apps
for org in "${all_orgs[@]}"; do
    echo "Checking GitHub Apps for organization: $org..."
    
    # Get installations for this organization
    installations_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/installations?per_page=100")
    installations_last_page=$(get_last_page "$installations_response_headers")
    
    # Track if we found any apps for this org
    found_apps=false
    
    # Fetch all pages of installations for this org
    for page in $(seq 1 $installations_last_page); do
        installations_page=$(github_api_get "/orgs/${org}/installations?per_page=100&page=$page")
        
        # Process each installation
        num_installations=$(echo "$installations_page" | jq '.installations | length')
        
        if [[ $num_installations -gt 0 ]]; then
            found_apps=true
            
            # Extract and print installation details
            echo "$installations_page" | jq -c '.installations[]' | while read -r installation; do
                app_name=$(echo "$installation" | jq -r '.app_name // "N/A"')
                app_id=$(echo "$installation" | jq -r '.app_id // "N/A"')
                
                # Extract some key permissions (modify this as needed to extract relevant permissions)
                permissions=$(echo "$installation" | jq -r '.permissions | to_entries | map("\(.key):\(.value)") | join(", ")')
                
                # Truncate permissions string if it's too long (using bash instead of jq for substring)
                if [[ ${#permissions} -gt 50 ]]; then
                    permissions="${permissions:0:50}..."
                fi
                
                printf "%-30s | %-40s | %-15s | %s\n" "$org" "$app_name" "$app_id" "$permissions"
            done
        fi
    done
    
    # If no apps were found, print a message
    if ! $found_apps; then
        printf "%-30s | %-40s | %-15s | %s\n" "$org" "No GitHub Apps installed" "-" "-"
    fi
done

echo "---------------------------------------------------------"
echo "Script completed successfully."
