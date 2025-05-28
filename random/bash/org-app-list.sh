#!/bin/bash
# Description: Lists all GitHub Apps installed in all organizations for either GHES or GHEC

# Configuration - Set these variables
# Default values that can be overridden by environment variables
: "${GITHUB_PAT:=your-personal-access-token}"
: "${GITHUB_ENV:=GHES}"  # Options: "GHES" or "GHEC"
: "${GITHUB_HOSTNAME:=your-github-enterprise-server.com}"  # e.g., github.example.com

# Default values for optional parameters
EXPORT_CSV=false
CSV_FILE="github_app_installations_$(date +%Y%m%d_%H%M%S).csv"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pat=*) GITHUB_PAT="${1#*=}" ;;
    --env=*) GITHUB_ENV="${1#*=}" ;;
    --hostname=*) GITHUB_HOSTNAME="${1#*=}" ;;
    --csv) EXPORT_CSV=true ;;
    --csv-file=*) EXPORT_CSV=true; CSV_FILE="${1#*=}" ;;
    --help) 
      echo "Usage: $0 [--pat=TOKEN] [--env=GHES|GHEC] [--hostname=hostname] [--csv] [--csv-file=FILENAME]" 
      echo "Options:"
      echo "  --pat=TOKEN         GitHub Personal Access Token"
      echo "  --env=GHES|GHEC    GitHub environment (GHES or GHEC)"
      echo "  --hostname=HOST     GitHub Enterprise Server hostname"
      echo "  --csv               Export results to CSV (default filename)"
      echo "  --csv-file=FILE     Export results to specified CSV file"
      echo "Or use environment variables: GITHUB_PAT, GITHUB_ENV, GITHUB_HOSTNAME"
      echo
      echo "Note: If an app name is not available, the app slug will be used instead."
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

# If CSV export is enabled, create the CSV header
if [[ "$EXPORT_CSV" == "true" ]]; then
    echo "Organization,App Name/Slug,App ID,Permissions" > "$CSV_FILE"
    echo "Results will be exported to: $CSV_FILE"
fi

echo "Organization GitHub App Installations:"
echo "---------------------------------------------------------"
printf "%-30s | %-40s | %-15s | %s\n" "Organization" "App Name/Slug" "App ID" "Permissions"
echo "---------------------------------------------------------"

# For each organization, get installed apps
for org in "${all_orgs[@]}"; do
    # Skip empty org names
    [[ -z "$org" ]] && continue
    
    echo "Checking GitHub Apps for organization: $org..."
    
    # Get installations for this organization
    installations_response_headers=$(curl -s -I -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github.v3+json" "${API_BASE}/orgs/${org}/installations?per_page=100")
    
    # Check if we got a valid response
    if [[ -z "$installations_response_headers" ]]; then
        echo "  Warning: Failed to get app installations for organization: $org"
        printf "%-30s | %-40s | %-15s | %s\n" "$org" "API ERROR" "-" "-"
        continue
    fi
    
    installations_last_page=$(get_last_page "$installations_response_headers")
    
    # Track if we found any apps for this org
    found_apps=false
    
    # Fetch all pages of installations for this org
    for page in $(seq 1 $installations_last_page); do
        installations_page=$(github_api_get "/orgs/${org}/installations?per_page=100&page=$page")
        
        # Check if response is valid JSON
        if ! echo "$installations_page" | jq empty 2>/dev/null; then
            echo "  Warning: Invalid JSON response for app installations in $org (page $page)"
            continue
        fi
        
        # Process each installation
        num_installations=$(echo "$installations_page" | jq '.installations | length')
        
        # Handle empty result
        if [[ -z "$num_installations" ]]; then
            num_installations=0
        fi
        
        if [[ $num_installations -gt 0 ]]; then
            found_apps=true
            
            # Extract and print installation details
            echo "$installations_page" | jq -c '.installations[]' | while read -r installation; do
                # Get app_name, fallback to app_slug if app_name is missing
                app_name=$(echo "$installation" | jq -r '.app_name // .app_slug // "Unknown"')
                app_id=$(echo "$installation" | jq -r '.app_id // "N/A"')
                
                # Extract some key permissions (modify this as needed to extract relevant permissions)
                permissions=$(echo "$installation" | jq -r '.permissions | to_entries | map("\(.key):\(.value)") | join(", ")')
                
                # Truncate permissions string if it's too long (using bash instead of jq for substring)
                if [[ ${#permissions} -gt 50 ]]; then
                    permissions="${permissions:0:50}..."
                fi
                
                # Print app details
                printf "%-30s | %-40s | %-15s | %s\n" "$org" "$app_name" "$app_id" "$permissions"
                
                # If CSV export is enabled, write to the CSV file
                if [[ "$EXPORT_CSV" == "true" ]]; then
                    # Properly escape fields for CSV
                    safe_org=$(echo "$org" | sed 's/"/""/g')
                    safe_app_name=$(echo "$app_name" | sed 's/"/""/g')
                    safe_permissions=$(echo "$permissions" | sed 's/"/""/g')
                    echo "\"$safe_org\",\"$safe_app_name\",\"$app_id\",\"$safe_permissions\"" >> "$CSV_FILE"
                fi
                
                # For more detailed analysis, you could extract additional info
                # target_id=$(echo "$installation" | jq -r '.target_id // "N/A"')
                # target_type=$(echo "$installation" | jq -r '.target_type // "N/A"')
                # echo "  Target ID: $target_id, Target Type: $target_type"
            done
        fi
    done
    
    # If no apps were found, print a message
    if ! $found_apps; then
        printf "%-30s | %-40s | %-15s | %s\n" "$org" "No GitHub Apps installed" "-" "-"
        
        # If CSV export is enabled, write to the CSV file
        if [[ "$EXPORT_CSV" == "true" ]]; then
            safe_org=$(echo "$org" | sed 's/"/""/g')
            echo "\"$safe_org\",\"No GitHub Apps installed\",\"-\",\"-\"" >> "$CSV_FILE"
        fi
    fi
done

# Define variables to track app statistics
total_orgs=${#all_orgs[@]}
total_orgs_with_apps=0
total_apps=0

# Now we need to count these stats
for org in "${all_orgs[@]}"; do
    # Get installations for this organization
    installations_data=$(github_api_get "/orgs/${org}/installations")
    
    # Skip invalid responses
    if ! echo "$installations_data" | jq empty &>/dev/null; then
        continue
    fi
    
    # Count installations
    org_installations=$(echo "$installations_data" | jq '.installations | length')
    
    # Handle empty results
    if [[ -z "$org_installations" ]]; then
        org_installations=0
    fi
    
    # If the org has installations, increment the counter
    if [[ $org_installations -gt 0 ]]; then
        ((total_orgs_with_apps++))
        ((total_apps+=org_installations))
    fi
done

echo "---------------------------------------------------------"
echo "Summary:"
echo "Total Organizations: $total_orgs"
echo "Organizations with GitHub Apps: $total_orgs_with_apps"
echo "Total GitHub App Installations: $total_apps"
if [[ "$EXPORT_CSV" == "true" ]]; then
    echo "Results exported to CSV: $CSV_FILE"
fi
echo "---------------------------------------------------------"
echo "Script completed successfully."
