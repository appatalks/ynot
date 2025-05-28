#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   GITHUB_TOKEN=ghp_xxx \
#   GITHUB_API_HOST=ghe.example.com \
#   ENTERPRISE_SLUG=your-enterprise-slug \ # NEEDED IF ON GHES
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

# --- Enterprise Slug Discovery ---

# If ENTERPRISE_SLUG is not set, attempt to auto-discover
if [[ -z "${ENTERPRISE_SLUG:-}" ]]; then
  echo "🔎 Attempting to discover your enterprise slug..."
  memberships=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" "$GITHUB_API/user/memberships/enterprises")
  slug_count=$(echo "$memberships" | jq 'length')
  if [[ "$slug_count" -eq 0 ]]; then
    echo "❌ No enterprise memberships found for your token. Please specify ENTERPRISE_SLUG manually."
    exit 1
  elif [[ "$slug_count" -eq 1 ]]; then
    ENTERPRISE_SLUG=$(echo "$memberships" | jq -r '.[0].enterprise.slug')
    echo "✅ Discovered enterprise slug: $ENTERPRISE_SLUG"
  else
    echo "⚠️  Multiple enterprises found:"
    echo "$memberships" | jq -r '.[].enterprise | "  - \(.slug): \(.name)"'
    echo "Please export ENTERPRISE_SLUG manually and rerun the script."
    exit 1
  fi
fi

echo "Fetching organizations for enterprise: $ENTERPRISE_SLUG"
orgs=()
page=1
while :; do
  response=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" \
    "$GITHUB_API/enterprises/$ENTERPRISE_SLUG/orgs?per_page=$per_page&page=$page")
  page_orgs=$(echo "$response" | jq -r '.[]?.login')
  [[ -z "$page_orgs" ]] && break
  orgs+=($page_orgs)
  ((page++))
done

if [[ ${#orgs[@]} -eq 0 ]]; then
  echo "No organizations found in enterprise."
  exit 1
fi

echo "Found ${#orgs[@]} orgs: ${orgs[*]}"
echo

for ORG in "${orgs[@]}"; do
  echo "Organization: $ORG"
  # Get self-hosted runners for org
  runner_count=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" \
    "$GITHUB_API/orgs/$ORG/actions/runners?per_page=1" | jq '.total_count')
  echo "  Self-hosted runners: $runner_count"

  # Get runner groups and print custom group counts
  runner_groups=$(curl -sSL -H "Authorization: Bearer $GITHUB_TOKEN" \
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
