#!/bin/bash
# Export ALL Repositories last 100 Pull Request Review Decisions
# This script uses both REST and GraphQL Endpoints
#
# Example Usage:
# $ bash run.sh
#     Please enter the organization name:
#     My-Super-Cool-ORG
#
# IMPORTANT: Use the best Authentication for your case
# https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api
#
# NOTE: Delay between API calls is hardcoded for 6 seconds at the last few lines of this script. Assuming 10K repositories, should take just under a day to run.

# Check if the required GitHub API token is set
if [ -z "$TOKEN" ]; then
  echo "Error: Please set the GitHub API token in the TOKEN environment variable."
  echo "Example: $ export TOKEN=ghp_****"
  exit 1
fi

# Ask for organization name
echo "Please enter the organization name: "
read orgName

# Set up GitHub API url
url="https://api.github.com/orgs/$orgName/repos?per_page=99"

# Define an empty array to store the repositories
repos=()

# Set the initial page to 1
page=1

# Use a while loop to iterate through all the pages
while true; do
  # Send GET request to the current page URL and retrieve the repositories
  page_repos=$(curl -s -H "Authorization: token $TOKEN" "$url&page=$page" | jq -r '.[] | .name, .private')

# Add the repositories to the array one by one
  while IFS= read -r repo; do
    repos+=("$repo")
  done <<< "$page_repos"

  # Send GET request to GitHub API and retrieve the response headers
  headers=$(curl -s -I -H "Authorization: token $TOKEN" "$url&page=$page")

  # Extract the "Link" header
  link_header=$(echo "$headers" | awk '/^link:/ {print $0}')
  echo ""
  echo "Discovering Repo Listing Standby: "
  echo ""
  echo $link_header
  echo ""

  # Check if "rel=next" is in the "link" header
  if echo "$link_header" | grep -q 'rel="next"'; then
    # "rel=next" is in the "link" header, so there is a next page
    next_page=1
  else
    # "rel=next" is not in the "link" header, so there is no next page
    next_page=0
  fi

  # Check if there is a next page
  if [ "$next_page" -eq 0 ]; then
    # No next page, so break the loop
    # echo "All pages discovered!"
    break
  fi

  # Increment the page counter
  ((page++))

  # Add a delay of n second between each REST API request
  sleep 6
  done

  # Print the array of repositories
  echo "--- echoing repos array ---"
  echo "${repos[@]}"

  #if [ ${repos[@]} -eq 0 ]; then
  #  echo "No repositories found for this organization, or the organization does not exist."
  #else
    echo "" > /tmp/repo_pr_review.tmp
    # Convert repos to array
    arr=(${repos[@]})

  # echo "--- echoing arr ---"
  # echo $arr

  # Iterate over arr by 2 (since each pair of entries is a repo name and its visibility)
  for ((i=0; i<${#arr[@]}; i+=2)); do
    # Convert visibility from boolean to human-readable string
    visibility="Public"
    if [ "${arr[$i+1]}" = "true" ]; then
      visibility="Private"
    fi

    # Get repo name
    repoName="${arr[$i]}"

    # Print repo name, visibility, and tag protection
    echo "$repoName" >> /tmp/repo_pr_review.tmp
  done
    echo ""
    echo "Discovered Repository Count: $(cat /tmp/repo_pr_review.tmp | wc -l)"

# Run GraphQL Query per Repo
ENDPOINT="https://api.github.com/graphql"

QUERY_TEMPLATE='{ "query": "query { repository(owner: \"__OWNER__\", name: \"__REPOSITORY__\") { pullRequests(last: 100, states: MERGED) { nodes { reviewDecision, mergedAt } } } }" }'

# Start Logging
qandr_log_file="/tmp/graphql_pr_review_query_response_raw-$(date +'%Y%m%d-%H%M%S').json"
export qandr_log_file=$qandr_log_file

response_log_file="/tmp/graphql_pr_review_response_raw-$(date +'%Y%m%d-%H%M%S').json"
export response_log_file=$response_log_file

for repository in $(cat /tmp/repo_pr_review.tmp); do
  # Replace __REPOSITORY__ with the current repository
  query="${QUERY_TEMPLATE/__OWNER__/$orgName}"
  query="${query/__REPOSITORY__/$repository}"

  # Make the API request
  response=$(curl -s -H "Authorization: bearer $TOKEN" -X POST -d "$query" "$ENDPOINT")

  log_query=$(echo $query)
  echo "---REPO QUERY FOR $repository ---" >> "$qandr_log_file"
  echo "$log_query\n" >> "$qandr_log_file"
  echo "" >> "$qandr_log_file"
  echo $response >> "$qandr_log_file"
  echo "---END RESPONSE---" >> "$qandr_log_file"
  echo "" >> "$qandr_log_file"
  echo "--- $repository" >> "$response_log_file"
  echo $response >> "$response_log_file"

# Check if the response contains the "data" field and "errors" field
if echo "$response" | jq '.data,.errors' &> /dev/null; then
  data_response=$(echo "$response" | jq '.data')
  errors_response=$(echo "$response" | jq '.errors')

  if [ "$errors_response" != "null" ]; then
    echo "\n "
    echo -e "\e[91mGraphQL query result (Errors):\e[0m"
    echo -e ""
    echo "$errors_response" | jq
  fi
fi
  # Add a delay of n second between each GraphQL API request
  sleep 6
  echo ""
  echo "Discovery ran on $repository. Proceeding to next Repository"
done
echo "Query and Response Log file saved to $qandr_log_file"
echo "JSON Response Log File Saved to $response_log_file"
