#!/usr/bin/env bash
set -euo pipefail

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
        
        page_orgs=$(echo "$response" | jq -r '.[].login')
        [[ -z "$page_orgs" ]] && break
        
        orgs+=($page_orgs)
        ((page++))
        
        # Safety check - don't fetch more than 10 pages
        if [[ "$page" -gt 10 ]]; then
          echo "⚠️  Reached page limit (10). If you have more than $(($per_page * 10)) organizations, adjust the script."
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
          
        # Check if response is empty
        org_count=$(echo "$response" | jq '.organizations | length')
        if [[ "$org_count" -eq 0 ]]; then
          break
        fi
        
        page_orgs=$(echo "$response" | jq -r '.organizations[].login')
        [[ -z "$page_orgs" ]] && break
        
        orgs+=($page_orgs)
        ((page++))
        
        # Safety check - don't fetch more than 10 pages
        if [[ "$page" -gt 10 ]]; then
          echo "⚠️  Reached page limit (10). If you have more than $(($per_page * 10)) organizations, adjust the script."
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
        
      # Check if response is empty
      org_count=$(echo "$response" | jq '.organizations | length')
      if [[ "$org_count" -eq 0 ]]; then
        break
      fi
      
      page_orgs=$(echo "$response" | jq -r '.organizations[].login')
      [[ -z "$page_orgs" ]] && break
      
      orgs+=($page_orgs)
      ((page++))
      
      # Safety check - don't fetch more than 10 pages
      if [[ "$page" -gt 10 ]]; then
        echo "⚠️  Reached page limit (10). If you have more than $(($per_page * 10)) organizations, adjust the script."
        break
      fi
    done
  fi
else
  # For GHES, simply get all organizations without needing enterprise slug
  echo "Fetching organizations from GitHub Enterprise Server ($GITHUB_API_HOST)"
  while :; do
    response=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
      "$GITHUB_API/organizations?per_page=$per_page&page=$page")
    
    # Check if response is empty or doesn't contain any organizations
    org_count=$(echo "$response" | jq '. | length')
    if [[ "$org_count" -eq 0 ]]; then
      break
    fi
    
    page_orgs=$(echo "$response" | jq -r '.[].login')
    [[ -z "$page_orgs" ]] && break
    
    orgs+=($page_orgs)
    ((page++))
    
    # Safety check - don't fetch more than 10 pages to avoid endless loops
    if [[ "$page" -gt 10 ]]; then
      echo "⚠️  Reached page limit (10). If you have more than $(($per_page * 10)) organizations, adjust the script."
      break
    fi
  done
fi

if [[ ${#orgs[@]} -eq 0 ]]; then
  echo "No organizations found in enterprise."
  exit 1
fi

echo "Found ${#orgs[@]} orgs: ${orgs[*]}"
echo

for ORG in "${orgs[@]}"; do
  echo "Organization: $ORG"
  # Get self-hosted runners for org
  runner_count=$(curl -sSL \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$GITHUB_API/orgs/$ORG/actions/runners?per_page=1" | jq '.total_count')
  echo "  Self-hosted runners: $runner_count"

  # Get runner groups and print custom group counts
  runner_groups=$(curl -sSL \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$GITHUB_API/orgs/$ORG/actions/runner-groups?per_page=100")
  group_count=$(echo "$runner_groups" | jq '.total_count')
  default_group_runners=$(echo "$runner_groups" | jq '[.runner_groups[] | select(.default)] | .[0].runners_count // 0')
  custom_group_runners=$(echo "$runner_groups" | jq '[.runner_groups[] | select(.default|not)] | map(.runners_count) | add // 0')
  echo "  Runner groups: $group_count"
  echo "    Default group runners: $default_group_runners"
  echo "    Custom group runners: $custom_group_runners"

  echo "  GitHub-hosted runners: Dynamic (not listable; billed by usage)"
  echo
done
