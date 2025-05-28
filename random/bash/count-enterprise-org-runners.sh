#!/usr/bin/env bash
set -euo pipefail

# Note: This script requires Bash 4.0 or higher for associative arrays

# Usage:
#   GITHUB_TOKEN=ghp_xxx \
#   GITHUB_API_HOST=ghe.example.com \  # Optional: Set for GitHub Enterprise Server, default is github.com
#   ENTERPRISE_SLUG=your-enterprise-slug \  # Optional: Only needed for GitHub.com Enterprise accounts
#   bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/random/bash/count-enterprise-org-runners.sh)

# Required: GitHub token with admin:enterprise or read:org scope
: "${GITHUB_TOKEN:?Must set GITHUB_TOKEN}"

# Optional: Set GITHUB_API_HOST to your GitHub server hostname (e.g., github.com or ghe.example.com)
# If not set, defaults to public GitHub API
GITHUB_API_HOST="${GITHUB_API_HOST:-github.com}"

# Construct GITHUB_API endpoint from GITHUB_API_HOST
if [[ "$GITHUB_API_HOST" == "github.com" ]]; then
  GITHUB_API="https://api.github.com"
else
  GITHUB_API="https://${GITHUB_API_HOST}/api/v3"
fi

per_page=100

# Determine how to fetch organizations based on API host
orgs=()
page=1

if [[ "$GITHUB_API_HOST" == "github.com" ]]; then
  # For GitHub.com, we need to handle Enterprise accounts differently
  # --- Enterprise Slug Discovery for GitHub.com ---
  if [[ -z "${ENTERPRISE_SLUG:-}" ]]; then
    echo "🔎 Attempting to discover your enterprise slug on GitHub.com..."
    memberships=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" "$GITHUB_API/user/memberships/enterprises")
    slug_count=$(echo "$memberships" | jq 'length')
    if [[ "$slug_count" -eq 0 ]]; then
      echo "ℹ️  No enterprise memberships found. Fetching organizations directly..."
      # User doesn't belong to an enterprise, fetch orgs directly
      while :; do
        response=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
          "$GITHUB_API/user/orgs?per_page=$per_page&page=$page")
          
        # Check if response is empty or doesn't contain any organizations
        org_count=$(echo "$response" | jq '. | length')
        if [[ "$org_count" -eq 0 ]]; then
          break
        fi
        
        # Extract organization names and add to the array
        while read -r org_name; do
          [[ -z "$org_name" ]] && continue
          orgs+=("$org_name")
        done < <(echo "$response" | jq -r '.[].login')
        
        ((page++))
        
        # Safety check - don't fetch more than 5 pages
        if [[ "$page" -gt 5 ]]; then
          echo "⚠️  Reached page limit (5). If you have more than $(($per_page * 5)) organizations, adjust the script."
          break
        fi
      done
    elif [[ "$slug_count" -eq 1 ]]; then
      ENTERPRISE_SLUG=$(echo "$memberships" | jq -r '.[0].enterprise.slug')
      echo "✅ Discovered enterprise slug: $ENTERPRISE_SLUG"
      echo "Fetching organizations for enterprise: $ENTERPRISE_SLUG"
      while :; do
        response=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
          "$GITHUB_API/enterprises/$ENTERPRISE_SLUG/orgs?per_page=$per_page&page=$page")
        
        # Check if response is empty - using grep -q for better compatibility
        if ! echo "$response" | grep -q '"organizations"'; then
          echo "⚠️  Invalid response from enterprise API. Check your enterprise slug and token permissions."
          break
        fi
        
        org_count=$(echo "$response" | jq '.organizations | length')
        if [[ "$org_count" -eq 0 ]]; then
          break
        fi
        
        # Extract organization names and add to the array
        while read -r org_name; do
          [[ -z "$org_name" ]] && continue
          orgs+=("$org_name")
        done < <(echo "$response" | jq -r '.organizations[].login')
        
        ((page++))
        
        # Safety check - don't fetch more than 5 pages
        if [[ "$page" -gt 5 ]]; then
          echo "⚠️  Reached page limit (5). If you have more than $(($per_page * 5)) organizations, adjust the script."
          break
        fi
      done
    else
      echo "⚠️  Multiple enterprises found:"
      echo "$memberships" | jq -r '.[].enterprise | "  - \(.slug): \(.name)"'
      echo "Please export ENTERPRISE_SLUG manually and rerun the script."
      exit 1
    fi
  else
    echo "Fetching organizations for enterprise: $ENTERPRISE_SLUG"
    while :; do
      response=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
        "$GITHUB_API/enterprises/$ENTERPRISE_SLUG/orgs?per_page=$per_page&page=$page")
        
      # Check if response is empty - using grep -q for better compatibility
      if ! echo "$response" | grep -q '"organizations"'; then
        echo "⚠️  Invalid response from enterprise API. Check your enterprise slug and token permissions."
        break
      fi
      
      org_count=$(echo "$response" | jq '.organizations | length')
      if [[ "$org_count" -eq 0 ]]; then
        break
      fi
      
      # Extract organization names and add to the array
      while read -r org_name; do
        [[ -z "$org_name" ]] && continue
        orgs+=("$org_name")
      done < <(echo "$response" | jq -r '.organizations[].login')
      
      ((page++))
      
      # Safety check - don't fetch more than 5 pages
      if [[ "$page" -gt 5 ]]; then
        echo "⚠️  Reached page limit (5). If you have more than $(($per_page * 5)) organizations, adjust the script."
        break
      fi
    done
  fi
else
  # For GHES, simply get all organizations without needing enterprise slug
  echo "Fetching organizations from GitHub Enterprise Server ($GITHUB_API_HOST)"
  
  # First try to get orgs the user is a member of - this is more reliable
  echo "Attempting to fetch organizations you're a member of..."
  while :; do
    response=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
      "$GITHUB_API/user/orgs?per_page=$per_page&page=$page")
    
    # Check if response is empty or doesn't contain any organizations
    org_count=$(echo "$response" | jq '. | length')
    if [[ "$org_count" -eq 0 ]]; then
      break
    fi
    
    # Extract unique organization names and add to the array
    # Use an associative array to track unique orgs
    while read -r org_name; do
      [[ -z "$org_name" ]] && continue
      orgs+=("$org_name")
    done < <(echo "$response" | jq -r '.[].login')
    
    ((page++))
    
    # Safety check - don't fetch more than 5 pages
    if [[ "$page" -gt 5 ]]; then
      echo "⚠️  Reached page limit (5) for user organizations."
      break
    fi
  done
fi

# Remove duplicate organizations (in case the API returned duplicates)
# This implementation is compatible with older Bash versions
unique_orgs_list=()

for org in "${orgs[@]}"; do
  # Check if the org is already in our unique list
  is_duplicate=0
  for unique_org in "${unique_orgs_list[@]}"; do
    if [[ "$org" == "$unique_org" ]]; then
      is_duplicate=1
      break
    fi
  done
  
  # If not a duplicate, add to our unique list
  if [[ $is_duplicate -eq 0 ]]; then
    unique_orgs_list+=("$org")
  fi
done

# Replace the original array with our deduplicated list
orgs=("${unique_orgs_list[@]}")

if [[ ${#orgs[@]} -eq 0 ]]; then
  echo "No organizations found that you have access to."
  exit 1
fi

echo "Found ${#orgs[@]} orgs: ${orgs[*]}"
echo

for ORG in "${orgs[@]}"; do
  echo "Organization: $ORG"
  
  # Get self-hosted runners for org (with error handling)
  # Using a simpler approach for older Bash versions
  runner_api_url="$GITHUB_API/orgs/$ORG/actions/runners?per_page=1"
  response_body=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$runner_api_url")
    
  # Check if the response contains an error message - simple approach for compatibility
  if echo "$response_body" | grep -q "message"; then
    status_code=403  # Assume forbidden if there's an error message
  else
    status_code=200  # Assume success if no error message
  fi
  
  if [[ "$status_code" -eq 200 ]]; then
    runner_count=$(echo "$response_body" | jq '.total_count')
    echo "  Self-hosted runners: $runner_count"
    
    # Get runner groups and print custom group counts
    # Using a simpler approach for older Bash versions
    group_api_url="$GITHUB_API/orgs/$ORG/actions/runner-groups?per_page=100"
    group_response_body=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$group_api_url")
      
    # Check if the response contains an error message - simple approach for compatibility
    if echo "$group_response_body" | grep -q "message"; then
      group_status_code=403  # Assume forbidden if there's an error message
    else
      group_status_code=200  # Assume success if no error message
    fi
    
    if [[ "$group_status_code" -eq 200 ]]; then
      group_count=$(echo "$group_response_body" | jq '.total_count')
      echo "  Runner groups: $group_count"
      
      # Check if we have runner_groups in the response - using grep -q for compatibility
      if echo "$group_response_body" | grep -q '"runner_groups"'; then
        # Use temporary files to store group runner counts since we're using while loops 
        # which run in subshells and can't modify parent variables
        tmp_default_runners=$(mktemp)
        tmp_custom_runners=$(mktemp)
        
        # Initialize the counter files
        echo "0" > "$tmp_default_runners"
        echo "0" > "$tmp_custom_runners"
        
        # Get all runner groups and their details
        group_ids=$(echo "$group_response_body" | jq -r '.runner_groups[] | "\(.id),\(.default),\(.runners_url)"')
        
        # Process each group
        echo "$group_ids" | while IFS=',' read -r group_id is_default runners_url; do
          # Make API call to get runners for this group
          group_runners_response=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "$runners_url")
            
          # Check if we can get the count
          if ! echo "$group_runners_response" | grep -q "message"; then
            group_runner_count=$(echo "$group_runners_response" | jq '.total_count')
            
            # Update the appropriate counter file
            if [ "$is_default" = "true" ]; then
              curr_count=$(cat "$tmp_default_runners")
              echo "$((curr_count + group_runner_count))" > "$tmp_default_runners"
            else 
              curr_count=$(cat "$tmp_custom_runners")
              echo "$((curr_count + group_runner_count))" > "$tmp_custom_runners"
            fi
          fi
        done
        
        # Read the final counts
        default_group_runners=$(cat "$tmp_default_runners")
        custom_group_runners=$(cat "$tmp_custom_runners")
        
        # Clean up temp files
        rm -f "$tmp_default_runners" "$tmp_custom_runners"
        
        echo "    Default group runners: $default_group_runners"
        echo "    Custom group runners: $custom_group_runners"
      else
        echo "    No runner groups data available"
      fi
    else
      # Simple error message extraction
      echo "$group_response_body" | grep -q '"message"' && {
        error_message=$(echo "$group_response_body" | grep -o '"message"[^,}]*' | sed 's/"message":*"//g;s/"//g')
        [ -z "$error_message" ] && error_message="Unknown error"
      } || {
        error_message="Unknown error"
      }
      echo "  Runner groups: Access denied - $error_message"
    fi
  else
    # Simple error message extraction
    echo "$response_body" | grep -q '"message"' && {
      error_message=$(echo "$response_body" | grep -o '"message"[^,}]*' | sed 's/"message":*"//g;s/"//g')
      [ -z "$error_message" ] && error_message="Unknown error"
    } || {
      error_message="Unknown error"
    }
    echo "  Access denied - $error_message"
  fi

  echo "  GitHub-hosted runners: Dynamic (not listable; billed by usage)"
  echo
done
