#!/bin/bash
#
# This script uses GitHub's GraphQL API to:
#   1. Retrieve pull requests from a specific repository.
#   2. For each PR, obtain the list of changed files.
#   3. Filter PRs to only those that changed files in the specified folder.
#   4. Optionally, filter results by PR author.
#
# Usage:
#   GITHUB_TOKEN=<your_pat> ./query_prs.sh <OWNER>/<REPO>/<target-folder> [author]
#
# Example:
#   GITHUB_TOKEN=abcdef123456 ./query_prs.sh appatalks/my-repo .github/workflows janedoe
#
# Before running, ensure:
#   - The GITHUB_TOKEN environment variable is set with appropriate permissions.
#   - The jq command is installed.

# Ensure required environment variable is set.
: "${GITHUB_TOKEN?Please set your GITHUB_TOKEN environment variable}"

# Validate and extract command line arguments.
if [ -z "$1" ]; then
  echo "Usage: $0 <OWNER>/<REPO>/<target-folder> [author]"
  exit 1
fi

IFS='/' read -r OWNER REPO TARGET_DIR <<< "$1"
if [ -z "$OWNER" ] || [ -z "$REPO" ] || [ -z "$TARGET_DIR" ]; then
  echo "Error: Argument must be in the format <OWNER>/<REPO>/<target-folder>."
  exit 1
fi

AUTHOR_FILTER="$2"
GRAPHQL_URL="https://api.github.com/graphql"

# Construct the search query to restrict to the specified repository.
SEARCH_QUERY="is:pr repo:${OWNER}/${REPO}"

# GraphQL query to search for PRs and retrieve changed files and author.
read -r -d '' GRAPHQL_QUERY <<'EOF'
query ($after: String, $searchQuery: String!) {
  search(query: $searchQuery, type: ISSUE, first: 50, after: $after) {
    edges {
      node {
        ... on PullRequest {
          number
          title
          url
          author {
            login
          }
          files(first: 100) {
            nodes {
              path
            }
          }
        }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
EOF

# Function to perform the GraphQL query with optional pagination cursor.
call_graphql() {
  local after_cursor="$1"
  if [ -n "$after_cursor" ]; then
    payload=$(jq -nc --arg query "$GRAPHQL_QUERY" \
                      --arg after "$after_cursor" \
                      --arg searchQuery "$SEARCH_QUERY" \
                      '{query: $query, variables: {after: $after, searchQuery: $searchQuery}}')
  else
    payload=$(jq -nc --arg query "$GRAPHQL_QUERY" \
                      --arg searchQuery "$SEARCH_QUERY" \
                      '{query: $query, variables: {after: null, searchQuery: $searchQuery}}')
  fi

  curl -s -H "Authorization: bearer $GITHUB_TOKEN" \
       -H "Content-Type: application/json" \
       -X POST \
       -d "$payload" "$GRAPHQL_URL"
}

echo "Searching in repository: ${OWNER}/${REPO}"
echo "Target folder: $TARGET_DIR"
if [ -n "$AUTHOR_FILTER" ]; then
  echo "Filtering results to those authored by: $AUTHOR_FILTER"
fi

after_cursor=""
while :; do
  response=$(call_graphql "$after_cursor")

  # Exit if there are GraphQL errors.
  if echo "$response" | jq -e '.errors' > /dev/null; then
    echo "GraphQL errors:"
    echo "$response" | jq '.errors'
    exit 1
  fi

  # Process each pull request from the current page.
  echo "$response" | jq -c '.data.search.edges[]' | while read -r edge; do
    pr=$(echo "$edge" | jq '.node')
    pr_number=$(echo "$pr" | jq '.number')
    pr_title=$(echo "$pr" | jq -r '.title')
    pr_url=$(echo "$pr" | jq -r '.url')
    pr_author=$(echo "$pr" | jq -r '.author.login // "unknown"')

    # Filter based on author if an author filter is provided.
    if [ -n "$AUTHOR_FILTER" ] && [ "$pr_author" != "$AUTHOR_FILTER" ]; then
      continue
    fi

    # Check files changed in the PR.
    file_matches=$(echo "$pr" | jq --arg target_dir "$TARGET_DIR" '[.files.nodes[]? | select(.path | startswith($target_dir))] | length')
    if [ "$file_matches" -gt 0 ]; then
      echo "---------------------------------------------"
      echo "PR #$pr_number: $pr_title"
      echo "URL: $pr_url"
      echo "Author: $pr_author"
      echo "Matched Files:"
      echo "$pr" | jq --arg target_dir "$TARGET_DIR" '.files.nodes[] | select(.path | startswith($target_dir)) | .path'
      echo "---------------------------------------------"
      echo
    fi
  done

  # Check if there are additional pages.
  has_next=$(echo "$response" | jq -r '.data.search.pageInfo.hasNextPage')
  if [ "$has_next" != "true" ]; then
    break
  fi
  after_cursor=$(echo "$response" | jq -r '.data.search.pageInfo.endCursor')
done
