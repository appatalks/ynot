#!/bin/bash

PrintUsage() {
  cat << EOM
Usage: ./get-repo-statistics [OPTIONS] [org-name]
Options:
    -h, --help                   : Show this message
    -d, --DEBUG                  : Enable debug mode
    -u, --url                    : GitHub Enterprise URL in the format: https://ghe-url.com
    -t, --token                  : GitHub Personal Access Token (PAT)
    -i, --input                  : Input file containing a list of orgs to process
    -r, --analyze-repo-conflicts : Gathers each org's repo list and checks against other orgs to generate a list of
                                    potential naming conflicts if those orgs are to be merged during migration
    -T, --analyze-team-conflicts : Gathers each org's teams and checks against other orgs to generate a list of
                                    potential naming conflicts if those orgs are to be merged during migration
    -p, --repo-page-size         : Set the pagination size for the initial repository GraphQL query - defaults to 20
                                    If a timeout occurs, reduce this value
    -e, --extra-page-size        : Set the pagination size for subsequent, paginated GraphQL queries - defaults to 20
                                    If a timeout occurs, reduce this value
    -j, --jobs                   : Number of parallel jobs to run (default: 4)
    -c, --cache                  : Use local cache for repository data (speeds up re-runs)
Description:
get-repo-statistics scans an organization or list of organizations for all repositories and gathers size statistics for each repository
Example:
  ./get-repo-statistics -u https://github.example.com -t ABCDEFG1234567 my-org-name
EOM
  exit 0
}

PARAMS=""
while (( "$#" )); do
  case "$1" in
    -h|--help)
      PrintUsage;
      ;;
    -u|--url)
      GHE_URL=$2
      shift 2
      ;;
    -d|--DEBUG)
      DEBUG=true
      shift
      ;;
    -t|--token)
      GITHUB_TOKEN=$2
      shift 2
      ;;
    -i|--input)
      INPUT_FILE_NAME=$2
      shift 2
      ;;
    -r|--analyze-repo-conflicts)
      ANALYZE_REPO_CONFLICTS=true
      shift
      ;;
    -T|--analyze-team-conflicts)
      ANALYZE_TEAM_CONFLICTS=true
      shift
      ;;
    -p|--repo-page-size)
      REPO_PAGE_SIZE=$2
      shift 2
      ;;
    -e|--extra-page-size)
      EXTRA_PAGE_SIZE=$2
      shift 2
      ;;
    -j|--jobs)
      PARALLEL_JOBS=$2
      shift 2
      ;;
    -c|--cache)
      USE_CACHE=true
      shift
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      PrintUsage
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# Set positional arguments in their proper place
eval set -- "$PARAMS"

# Defaults for parameters not directly passed
DEBUG=${DEBUG:-false}
GHE_URL=${GHE_URL:-https://api.github.com}
ANALYZE_REPO_CONFLICTS=${ANALYZE_REPO_CONFLICTS:-false}
ANALYZE_TEAM_CONFLICTS=${ANALYZE_TEAM_CONFLICTS:-false}
REPO_PAGE_SIZE=${REPO_PAGE_SIZE:-20}
EXTRA_PAGE_SIZE=${EXTRA_PAGE_SIZE:-20}
PARALLEL_JOBS=${PARALLEL_JOBS:-4} # Default to 4 parallel jobs
USE_CACHE=${USE_CACHE:-false}

# Utility functions
ConvertKBToMB() {
  # Convert KB to MB, rounding to 2 decimal places
  local KB_VALUE=$1
  if [ -z "$KB_VALUE" ]; then
    echo "0.00"
  else
    awk "BEGIN {printf \"%.2f\", $KB_VALUE/1024}"
  fi
}

# Global jq helper function - defined globally to avoid scope issues
base64_jq() {
  local encoded_data=$1
  local jq_query=$2
  echo "${encoded_data}" | base64 --decode | jq -r "${jq_query}"
}

# For issue processing
issue_jq() {
  local ISSUE=$1
  local QUERY=$2
  echo "${ISSUE}" | jq -r "${QUERY}"
}

# For PR processing
pr_jq() {
  local PR=$1
  local QUERY=$2
  echo "${PR}" | jq -r "${QUERY}"
}

# For review processing
review_jq() {
  local REVIEW=$1
  local QUERY=$2
  echo "${REVIEW}" | jq -r "${QUERY}"
}

# Debug helper - shows JSON output if DEBUG mode enabled
DebugJQ() {
  if [ "${DEBUG}" == "true" ]; then
    echo "$1" | jq '.'
  fi
}

# Rate limiting helper
GetGitHubRateLimit() {
  GITHUB_RATE_LIMIT=$(curl -s \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    ${GHE_URL}/rate_limit \
    |  jq -r '.resources.graphql.remaining' 2>&1)

  if [ $? -ne 0 ] || [ -z "${GITHUB_RATE_LIMIT}" ]; then
    echo "Unable to check rate limit. Assuming we're not being rate limited..."
    return 0
  fi

  if [ ${GITHUB_RATE_LIMIT} -lt 100 ]; then
    RESET_TIME=$(curl -s \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      ${GHE_URL}/rate_limit \
      | jq -r '.resources.graphql.reset')
      
    CURRENT_TIME=$(date +%s)
    SLEEP_TIME=$((RESET_TIME - CURRENT_TIME + 60))
    
    if [ ${SLEEP_TIME} -gt 0 ]; then
      echo "Rate limit reached. Sleeping for ${SLEEP_TIME} seconds..."
      sleep ${SLEEP_TIME}
    fi
  fi
}

# Global GitHub API query function
GitHubAPIQuery() {
  local QUERY=$1
  local RETRIES=3
  local RETRY_DELAY=5
  local SUCCESS=false
  local ATTEMPT=1
  local RESPONSE=""

  while [ $ATTEMPT -le $RETRIES ] && [ "$SUCCESS" = "false" ]; do
    if [ $ATTEMPT -gt 1 ]; then
      echo "Retry attempt $ATTEMPT for API query..."
      sleep $RETRY_DELAY
      # Increase delay for next retry
      RETRY_DELAY=$((RETRY_DELAY * 2))
    fi

    # Check rate limit before making the query
    GetGitHubRateLimit

    RESPONSE=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Content-Type: application/json" \
      -X POST -d "${QUERY}" \
      "${GHE_URL}/graphql")

    # Check for errors in the response
    ERROR_MESSAGE=$(echo "${RESPONSE}" | jq -r '.errors[]?.message' 2>/dev/null)
    if [ -z "${ERROR_MESSAGE}" ] || [ "${ERROR_MESSAGE}" = "null" ]; then
      SUCCESS=true
    else
      echo "Error in attempt $ATTEMPT: ${ERROR_MESSAGE}"
      ATTEMPT=$((ATTEMPT + 1))
    fi
  done

  if [ "$SUCCESS" = "false" ]; then
    echo "Failed to complete API query after $RETRIES attempts" >&2
    return 1
  fi

  echo "${RESPONSE}"
}

# Process repositories data
ParseRepoData() {
  PARSE_DATA=$1
  REPOS=$(echo "${PARSE_DATA}" | jq -r '.data.organization.repositories.nodes')
  
  # Create a temporary file with all repos data
  REPO_LIST_FILE="${PROCESSING_TMP_DIR}/repo_list_$$"
  echo "${REPOS}" | jq -r '.[] | @base64' > "${REPO_LIST_FILE}"
}

# Process a single repository
process_repo() {
  local REPO=$1
  
  # Use the global base64_jq function
  local OWNER=$(base64_jq "${REPO}" '.owner.login' | tr '[:upper:]' '[:lower:]')
  local REPO_NAME=$(base64_jq "${REPO}" '.name' | tr '[:upper:]' '[:lower:]')
  
  # Skip if already analyzed
  if grep -q "${OWNER},${REPO_NAME}," "${OUTPUT_FILE_NAME}" 2>/dev/null; then
    echo "Repo:[${OWNER}/${REPO_NAME}] has previously been analyzed, moving on..."
    return 0
  fi
  
  echo "Analyzing Repo: ${REPO_NAME}"
  
  local REPO_SIZE_KB=$(base64_jq "${REPO}" '.diskUsage')
  local REPO_SIZE=$(ConvertKBToMB "${REPO_SIZE_KB}")
  local IS_EMPTY=$(base64_jq "${REPO}" '.isEmpty')
  local PUSHED_AT=$(base64_jq "${REPO}" '.pushedAt')
  local UPDATED_AT=$(base64_jq "${REPO}" '.updatedAt')
  local IS_FORK=$(base64_jq "${REPO}" '.isFork')
  local MILESTONE_CT=$(base64_jq "${REPO}" '.milestones.totalCount')
  local COLLABORATOR_CT=$(base64_jq "${REPO}" '.collaborators.totalCount')
  local PR_CT=$(base64_jq "${REPO}" '.pullRequests.totalCount')
  local ISSUE_CT=$(base64_jq "${REPO}" '.issues.totalCount')
  local RELEASE_CT=$(base64_jq "${REPO}" '.releases.totalCount')
  local COMMIT_COMMENT_CT=$(base64_jq "${REPO}" '.commitComments.totalCount')
  local PROJECT_CT=$(base64_jq "${REPO}" '.projects.totalCount')
  
  local PROTECTED_BRANCH_CT
  if [[ "${VERSION}" == "cloud" || $(echo "${VERSION:0:3} >= 2.17" | bc -l) ]]; then
    PROTECTED_BRANCH_CT=$(base64_jq "${REPO}" '.branchProtectionRules.totalCount')
  else
    PROTECTED_BRANCH_CT=$(base64_jq "${REPO}" '.protectedBranches.totalCount')
  fi
  
  local ISSUE_EVENT_CT=0
  local ISSUE_COMMENT_CT=0
  local PR_REVIEW_CT=0
  local PR_REVIEW_COMMENT_CT=0
  
  # Process issues and PRs 
  local ISSUES=$(base64_jq "${REPO}" '.issues.nodes')
  local PRS=$(base64_jq "${REPO}" '.pullRequests.nodes')
  
  # Process issues
  if [ "${ISSUE_CT}" -gt 0 ]; then
    local ISSUE_NEXT_PAGE=$(base64_jq "${REPO}" '.issues.pageInfo.hasNextPage')
    if [ "${ISSUE_NEXT_PAGE}" == "true" ]; then
      local ISSUE_END_CURSOR=$(base64_jq "${REPO}" '.issues.pageInfo.endCursor')
      local ADDITIONAL_ISSUE_STATS=$(get_remaining_issues "${OWNER}" "${REPO_NAME}" ", after: \"${ISSUE_END_CURSOR}\"")
      
      # Parse additional stats
      local ADDITIONAL_ISSUE_EVENT_CT=$(echo "${ADDITIONAL_ISSUE_STATS}" | jq -r '.issue_event_count')
      local ADDITIONAL_ISSUE_COMMENT_CT=$(echo "${ADDITIONAL_ISSUE_STATS}" | jq -r '.issue_comment_count')
      
      ISSUE_EVENT_CT=$((ISSUE_EVENT_CT + ADDITIONAL_ISSUE_EVENT_CT))
      ISSUE_COMMENT_CT=$((ISSUE_COMMENT_CT + ADDITIONAL_ISSUE_COMMENT_CT))
    fi
    
    # Process current page of issues
    for ISSUE in $(echo "${ISSUES}" | jq -r '.[] | @base64'); do
      local ISSUE_ID=$(issue_jq "${ISSUE}" '.id')
      local ISSUE_COMMENTS=$(issue_jq "${ISSUE}" '.comments.totalCount')
      
      ISSUE_COMMENT_CT=$((ISSUE_COMMENT_CT + ISSUE_COMMENTS))
      
      # Count timeline events
      local TIMELINE_ITEMS=$(issue_jq "${ISSUE}" '.timelineItems.totalCount')
      ISSUE_EVENT_CT=$((ISSUE_EVENT_CT + TIMELINE_ITEMS))
    done
  fi
  
  # Process PRs
  if [ "${PR_CT}" -gt 0 ]; then
    local PR_NEXT_PAGE=$(base64_jq "${REPO}" '.pullRequests.pageInfo.hasNextPage')
    if [ "${PR_NEXT_PAGE}" == "true" ]; then
      local PR_END_CURSOR=$(base64_jq "${REPO}" '.pullRequests.pageInfo.endCursor')
      local ADDITIONAL_PR_STATS=$(get_remaining_prs "${OWNER}" "${REPO_NAME}" ", after: \"${PR_END_CURSOR}\"")
      
      # Parse additional stats
      local ADDITIONAL_PR_REVIEW_CT=$(echo "${ADDITIONAL_PR_STATS}" | jq -r '.pr_review_count')
      local ADDITIONAL_PR_REVIEW_COMMENT_CT=$(echo "${ADDITIONAL_PR_STATS}" | jq -r '.pr_review_comment_count')
      
      PR_REVIEW_CT=$((PR_REVIEW_CT + ADDITIONAL_PR_REVIEW_CT))
      PR_REVIEW_COMMENT_CT=$((PR_REVIEW_COMMENT_CT + ADDITIONAL_PR_REVIEW_COMMENT_CT))
    fi
    
    # Process current page of PRs
    for PR in $(echo "${PRS}" | jq -r '.[] | @base64'); do
      local PR_NUMBER=$(pr_jq "${PR}" '.number')
      local PR_REVIEWS=$(pr_jq "${PR}" '.reviews.totalCount')
      
      PR_REVIEW_CT=$((PR_REVIEW_CT + PR_REVIEWS))
      
      # Process reviews on this PR if there are any
      if [ "${PR_REVIEWS}" -gt 0 ]; then
        local REVIEWS=$(pr_jq "${PR}" '.reviews.nodes')
        local REVIEW_NEXT_PAGE=$(pr_jq "${PR}" '.reviews.pageInfo.hasNextPage')
        
        if [ "${REVIEW_NEXT_PAGE}" == "true" ]; then
          local REVIEW_END_CURSOR=$(pr_jq "${PR}" '.reviews.pageInfo.endCursor')
          local ADDITIONAL_REVIEW_STATS=$(get_remaining_reviews "${OWNER}" "${REPO_NAME}" "${PR_NUMBER}" ", after: \"${REVIEW_END_CURSOR}\"")
          
          # Add to our counts
          local ADDITIONAL_REVIEW_COMMENT_CT=$(echo "${ADDITIONAL_REVIEW_STATS}" | jq -r '.review_comment_count')
          PR_REVIEW_COMMENT_CT=$((PR_REVIEW_COMMENT_CT + ADDITIONAL_REVIEW_COMMENT_CT))
        fi
        
        # Process the current page of reviews
        for REVIEW in $(echo "${REVIEWS}" | jq -r '.[] | @base64'); do
          local COMMENTS=$(review_jq "${REVIEW}" '.comments.totalCount')
          PR_REVIEW_COMMENT_CT=$((PR_REVIEW_COMMENT_CT + COMMENTS))
        done
      fi
    done
  fi
  
  # Output the stats
  echo "${OWNER},${REPO_NAME},${REPO_SIZE},${IS_EMPTY},${PUSHED_AT},${UPDATED_AT},${IS_FORK},${MILESTONE_CT},${PROTECTED_BRANCH_CT},${COLLABORATOR_CT},${PR_CT},${PR_REVIEW_CT},${PR_REVIEW_COMMENT_CT},${ISSUE_CT},${ISSUE_COMMENT_CT},${ISSUE_EVENT_CT},${RELEASE_CT},${COMMIT_COMMENT_CT},${PROJECT_CT}" >> "${OUTPUT_FILE_NAME}"
}

# Process repositories with batch processing
ProcessRepos() {
  # Note: We're using a FIFO queue for parallel processing without GNU parallel
  echo "Processing ${REPO_PAGE_SIZE} repositories with improved efficiency..."
  
  # Create a FIFO queue for parallel processing
  FIFO="${PROCESSING_TMP_DIR}/repo_fifo"
  mkfifo "$FIFO"
  
  # Start background processes to handle repositories
  for ((i=1; i<=${PARALLEL_JOBS}; i++)); do
    (
      while read -r REPO; do
        if [ -n "$REPO" ]; then
          process_repo "$REPO"
        fi
      done < "$FIFO"
    ) &
  done
  
  # Feed the FIFO with repo data
  (
    cat "${REPO_LIST_FILE}"
    # Send termination signals
    for ((i=1; i<=${PARALLEL_JOBS}; i++)); do
      echo ""
    done
  ) > "$FIFO"
  
  # Wait for all background processes to complete
  wait
  
  # Clean up FIFO
  rm -f "$FIFO"
}

# Get all remaining issues for a repo with pagination
get_remaining_issues() {
  local OWNER=$1
  local REPO_NAME=$2
  local NEXT_PAGE=$3
  local EVENT_COUNT=0
  local COMMENT_COUNT=0
  local RETRIES=3
  
  # GraphQL query for issues
  local QUERY="{ \"query\": \"query { repository(owner: \\\"${OWNER}\\\", name: \\\"${REPO_NAME}\\\") { issues(first: ${EXTRA_PAGE_SIZE} ${NEXT_PAGE}) { pageInfo { hasNextPage endCursor } nodes { id comments { totalCount } timelineItems { totalCount } } } } }\" }"
  
  for attempt in $(seq 1 $RETRIES); do
    local RESPONSE=$(GitHubAPIQuery "${QUERY}")
    
    if [ $? -eq 0 ]; then
      local ISSUES=$(echo "${RESPONSE}" | jq -r '.data.repository.issues.nodes')
      local HAS_NEXT_PAGE=$(echo "${RESPONSE}" | jq -r '.data.repository.issues.pageInfo.hasNextPage')
      
      # Process each issue
      for ISSUE in $(echo "${ISSUES}" | jq -r '.[] | @base64'); do
        local ISSUE_COMMENTS=$(issue_jq "${ISSUE}" '.comments.totalCount')
        COMMENT_COUNT=$((COMMENT_COUNT + ISSUE_COMMENTS))
        
        # Count timeline events
        local TIMELINE_ITEMS=$(issue_jq "${ISSUE}" '.timelineItems.totalCount')
        EVENT_COUNT=$((EVENT_COUNT + TIMELINE_ITEMS))
      done
      
      # Handle pagination
      if [ "${HAS_NEXT_PAGE}" == "true" ]; then
        local END_CURSOR=$(echo "${RESPONSE}" | jq -r '.data.repository.issues.pageInfo.endCursor')
        local NEXT_QUERY=", after: \\\"${END_CURSOR}\\\""
        
        # Get additional pages
        local ADDITIONAL_STATS=$(get_remaining_issues "${OWNER}" "${REPO_NAME}" "${NEXT_QUERY}")
        local ADDITIONAL_EVENT_COUNT=$(echo "${ADDITIONAL_STATS}" | jq -r '.issue_event_count')
        local ADDITIONAL_COMMENT_COUNT=$(echo "${ADDITIONAL_STATS}" | jq -r '.issue_comment_count')
        
        EVENT_COUNT=$((EVENT_COUNT + ADDITIONAL_EVENT_COUNT))
        COMMENT_COUNT=$((COMMENT_COUNT + ADDITIONAL_COMMENT_COUNT))
      fi
      
      break
    else
      if [ $attempt -lt $RETRIES ]; then
        echo "Retry $attempt for issues query failed. Retrying in 5 seconds..."
        sleep 5
      else
        echo "Failed to get issues after $RETRIES attempts" >&2
      fi
    fi
  done
  
  # Return the counts as JSON for easier parsing
  echo "{\"issue_event_count\": ${EVENT_COUNT}, \"issue_comment_count\": ${COMMENT_COUNT}}"
}

# Get all remaining PRs for a repo with pagination
get_remaining_prs() {
  local OWNER=$1
  local REPO_NAME=$2
  local NEXT_PAGE=$3
  local REVIEW_COUNT=0
  local REVIEW_COMMENT_COUNT=0
  local RETRIES=3
  
  # GraphQL query for PRs
  local QUERY="{ \"query\": \"query { repository(owner: \\\"${OWNER}\\\", name: \\\"${REPO_NAME}\\\") { pullRequests(first: ${EXTRA_PAGE_SIZE} ${NEXT_PAGE}) { pageInfo { hasNextPage endCursor } nodes { number reviews(first: 20) { totalCount pageInfo { hasNextPage endCursor } nodes { comments { totalCount } } } } } } }\" }"
  
  for attempt in $(seq 1 $RETRIES); do
    local RESPONSE=$(GitHubAPIQuery "${QUERY}")
    
    if [ $? -eq 0 ]; then
      local PRS=$(echo "${RESPONSE}" | jq -r '.data.repository.pullRequests.nodes')
      local HAS_NEXT_PAGE=$(echo "${RESPONSE}" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage')
      
      # Process each PR
      for PR in $(echo "${PRS}" | jq -r '.[] | @base64'); do
        local PR_NUMBER=$(pr_jq "${PR}" '.number')
        local PR_REVIEWS=$(pr_jq "${PR}" '.reviews.totalCount')
        
        REVIEW_COUNT=$((REVIEW_COUNT + PR_REVIEWS))
        
        # Process reviews on this PR if there are any
        if [ "${PR_REVIEWS}" -gt 0 ]; then
          local REVIEWS=$(pr_jq "${PR}" '.reviews.nodes')
          local REVIEW_NEXT_PAGE=$(pr_jq "${PR}" '.reviews.pageInfo.hasNextPage')
          
          for REVIEW in $(echo "${REVIEWS}" | jq -r '.[] | @base64'); do
            local COMMENTS=$(review_jq "${REVIEW}" '.comments.totalCount')
            REVIEW_COMMENT_COUNT=$((REVIEW_COMMENT_COUNT + COMMENTS))
          done
          
          # Check for additional review pages
          if [ "${REVIEW_NEXT_PAGE}" == "true" ]; then
            local REVIEW_END_CURSOR=$(pr_jq "${PR}" '.reviews.pageInfo.endCursor')
            local REVIEWS_STATS=$(get_remaining_reviews "${OWNER}" "${REPO_NAME}" "${PR_NUMBER}" ", after: \\\"${REVIEW_END_CURSOR}\\\"")
            
            # Add to our counts
            local ADDITIONAL_REVIEW_COMMENT_CT=$(echo "${REVIEWS_STATS}" | jq -r '.review_comment_count')
            REVIEW_COMMENT_COUNT=$((REVIEW_COMMENT_COUNT + ADDITIONAL_REVIEW_COMMENT_CT))
          fi
        fi
      done
      
      # Handle pagination
      if [ "${HAS_NEXT_PAGE}" == "true" ]; then
        local END_CURSOR=$(echo "${RESPONSE}" | jq -r '.data.repository.pullRequests.pageInfo.endCursor')
        local NEXT_QUERY=", after: \\\"${END_CURSOR}\\\""
        
        # Get additional pages
        local ADDITIONAL_STATS=$(get_remaining_prs "${OWNER}" "${REPO_NAME}" "${NEXT_QUERY}")
        local ADDITIONAL_REVIEW_CT=$(echo "${ADDITIONAL_STATS}" | jq -r '.pr_review_count')
        local ADDITIONAL_REVIEW_COMMENT_CT=$(echo "${ADDITIONAL_STATS}" | jq -r '.pr_review_comment_count')
        
        REVIEW_COUNT=$((REVIEW_COUNT + ADDITIONAL_REVIEW_CT))
        REVIEW_COMMENT_COUNT=$((REVIEW_COMMENT_COUNT + ADDITIONAL_REVIEW_COMMENT_CT))
      fi
      
      break
    else
      if [ $attempt -lt $RETRIES ]; then
        echo "Retry $attempt for PRs query failed. Retrying in 5 seconds..."
        sleep 5
      else
        echo "Failed to get PRs after $RETRIES attempts" >&2
      fi
    fi
  done
  
  # Return the counts as JSON for easier parsing
  echo "{\"pr_review_count\": ${REVIEW_COUNT}, \"pr_review_comment_count\": ${REVIEW_COMMENT_COUNT}}"
}

# Get all remaining reviews for a PR with pagination
get_remaining_reviews() {
  local OWNER=$1
  local REPO_NAME=$2
  local PR_NUMBER=$3
  local NEXT_PAGE=$4
  local COMMENT_COUNT=0
  local RETRIES=3
  
  # GraphQL query for PR reviews
  local QUERY="{ \"query\": \"query { repository(owner: \\\"${OWNER}\\\", name: \\\"${REPO_NAME}\\\") { pullRequest(number: ${PR_NUMBER}) { reviews(first: ${EXTRA_PAGE_SIZE} ${NEXT_PAGE}) { pageInfo { hasNextPage endCursor } nodes { comments { totalCount } } } } } }\" }"
  
  for attempt in $(seq 1 $RETRIES); do
    local RESPONSE=$(GitHubAPIQuery "${QUERY}")
    
    if [ $? -eq 0 ]; then
      local REVIEWS=$(echo "${RESPONSE}" | jq -r '.data.repository.pullRequest.reviews.nodes')
      local HAS_NEXT_PAGE=$(echo "${RESPONSE}" | jq -r '.data.repository.pullRequest.reviews.pageInfo.hasNextPage')
      
      # Process each review
      for REVIEW in $(echo "${REVIEWS}" | jq -r '.[] | @base64'); do
        local REVIEW_COMMENTS=$(review_jq "${REVIEW}" '.comments.totalCount')
        COMMENT_COUNT=$((COMMENT_COUNT + REVIEW_COMMENTS))
      done
      
      # Handle pagination
      if [ "${HAS_NEXT_PAGE}" == "true" ]; then
        local END_CURSOR=$(echo "${RESPONSE}" | jq -r '.data.repository.pullRequest.reviews.pageInfo.endCursor')
        local NEXT_QUERY=", after: \\\"${END_CURSOR}\\\""
        
        # Get additional pages
        local ADDITIONAL_STATS=$(get_remaining_reviews "${OWNER}" "${REPO_NAME}" "${PR_NUMBER}" "${NEXT_QUERY}")
        local ADDITIONAL_COMMENT_COUNT=$(echo "${ADDITIONAL_STATS}" | jq -r '.review_comment_count')
        
        COMMENT_COUNT=$((COMMENT_COUNT + ADDITIONAL_COMMENT_COUNT))
      fi
      
      break
    else
      if [ $attempt -lt $RETRIES ]; then
        echo "Retry $attempt for reviews query failed. Retrying in 5 seconds..."
        sleep 5
      else
        echo "Failed to get reviews after $RETRIES attempts" >&2
      fi
    fi
  done
  
  # Return the count as JSON for easier parsing
  echo "{\"review_comment_count\": ${COMMENT_COUNT}}"
}

# Get organizations to process
ProcessOrgs() {
  ORG_LIST=()
  
  # Process org list from file if input file is specified
  if [ -n "${INPUT_FILE_NAME}" ]; then
    if [ ! -f "${INPUT_FILE_NAME}" ]; then
      echo "File not found: ${INPUT_FILE_NAME}"
      exit 1
    fi
    
    while IFS= read -r line || [ -n "$line" ]; do
      ORG_LIST+=("$line")
    done < "${INPUT_FILE_NAME}"
  else
    # Otherwise, use the org name from command line
    if [ -z "$1" ]; then
      echo "Error: No organization specified!"
      PrintUsage
    fi
    ORG_LIST+=("$1")
  fi
  
  # Create a directory for temporary files
  PROCESSING_TMP_DIR=$(mktemp -d)
  trap 'rm -rf -- "$PROCESSING_TMP_DIR"' EXIT
  
  # Process each organization
  for ORG_NAME in "${ORG_LIST[@]}"; do
    echo "Processing organization: ${ORG_NAME}"
    ProcessOrg "${ORG_NAME}"
  done
}

# Main function to process an organization
ProcessOrg() {
  local ORG_NAME=$1
  OUTPUT_FILE_NAME="${ORG_NAME}-repo-stats.csv"
  
  # Check if we should use cache
  if [ "${USE_CACHE}" == "true" ] && [ -f "${OUTPUT_FILE_NAME}" ]; then
    echo "Using cached repository data for ${ORG_NAME}"
  else
    # Initialize CSV output file with headers
    echo "Owner,Repository,Size(MB),IsEmpty,PushedAt,UpdatedAt,IsFork,Milestones,ProtectedBranches,Collaborators,PullRequests,PRReviews,PRReviewComments,Issues,IssueComments,IssueEvents,Releases,CommitComments,Projects" > "${OUTPUT_FILE_NAME}"
    
    # Get repository data
    GetRepos "${ORG_NAME}"
  fi
}

# Function to get all repositories for an organization
GetRepos() {
  local ORG_NAME=$1
  local REPO_NEXT_PAGE=""
  local REPO_LIST=()
  
  # Create GraphQL query to get repos data
  local QUERY="{ \"query\": \"query { organization(login: \\\"${ORG_NAME}\\\") { repositories(first: ${REPO_PAGE_SIZE} ${REPO_NEXT_PAGE}) { pageInfo { hasNextPage endCursor } nodes { owner { login } name diskUsage isEmpty pushedAt updatedAt isFork milestones { totalCount } collaborators { totalCount } pullRequests(first: 20) { pageInfo { hasNextPage endCursor } totalCount nodes { number reviews(first: 20) { pageInfo { hasNextPage endCursor } totalCount nodes { comments { totalCount } } } } } issues(first: 20) { pageInfo { hasNextPage endCursor } totalCount nodes { id comments { totalCount } timelineItems { totalCount } } } releases { totalCount } commitComments { totalCount } projects { totalCount } branchProtectionRules { totalCount } protectedBranches { totalCount } } } } }\" }"
  
  local DATA_BLOCK=$(GitHubAPIQuery "${QUERY}")
  
  if [ $? -eq 0 ]; then
    DebugJQ "${DATA_BLOCK}"
    local ERROR_MESSAGE=$(echo "${DATA_BLOCK}" | jq -r '.errors[]?')
    
    if [ -n "${ERROR_MESSAGE}" ] && [ "${ERROR_MESSAGE}" != "null" ]; then
      echo "GraphQL query returned an error: ${ERROR_MESSAGE}"
      echo "${DATA_BLOCK}" | jq '.'
    else
      HAS_NEXT_PAGE=$(echo "${DATA_BLOCK}" | jq -r '.data.organization.repositories.pageInfo.hasNextPage')
      REPO_NEXT_PAGE=', after: \"'$(echo "${DATA_BLOCK}" | jq -r '.data.organization.repositories.pageInfo.endCursor')'\"'
      
      ParseRepoData "${DATA_BLOCK}"
      ProcessRepos
      
      # Check for more pages
      if [ "${HAS_NEXT_PAGE}" == "false" ]; then
        REPO_NEXT_PAGE=""
      elif [ "${HAS_NEXT_PAGE}" == "true" ]; then
        GetRepos "${ORG_NAME}"
      else
        echo "Please validate your PAT, Organization, and access levels!"
      fi
    fi
  else
    echo "Failed to query GitHub API. Please check your token and permissions."
    exit 1
  fi
}

# Main execution starts here
if [ -z "${GITHUB_TOKEN}" ]; then
  echo "GitHub token not provided. Please provide a token using the -t flag."
  exit 1
fi

# Detect GitHub instance version
if [[ "${GHE_URL}" != *"api.github.com"* ]]; then
  META_DATA=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "${GHE_URL}/meta")
  DebugJQ "${META_DATA}"
  
  VERSION=$(echo "${META_DATA}" | jq -r '.installed_version')
  if [ -z "${VERSION}" ] || [ "${VERSION}" == "null" ]; then
    VERSION="cloud"
  fi
else
  VERSION="cloud"
fi

# Check GitHub user access
USER_DATA=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "${GHE_URL}/user")
DebugJQ "${USER_DATA}"

USER_LOGIN=$(echo "${USER_DATA}" | jq -r '.login')
if [ -z "${USER_LOGIN}" ] || [ "${USER_LOGIN}" == "null" ]; then
  echo "Unable to authenticate with provided token!"
  exit 1
fi

echo "Authenticated as: ${USER_LOGIN}"
echo "Using GitHub instance: ${GHE_URL} (${VERSION})"

# Start processing
ProcessOrgs "$@"

echo "Done!"
exit 0
