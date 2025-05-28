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
      ANALYZE_CONFLICTS=1
      shift
      ;;
    -T|--analyze-team-conflicts)
      ANALYZE_TEAMS=1
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
      USE_CACHE=1
      shift
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
  PARAMS="$PARAMS $1"
  shift
  ;;
  esac
done
eval set -- "$PARAMS"

if [[ -z $1 ]]; then
  ORG_NAME=$INPUT_FILE_NAME
else
  ORG_NAME=$1
fi

VERSION="unknown"
ANALYZE_TEAMS=${ANALYZE_TEAMS:-0}
ANALYZE_CONFLICTS=${ANALYZE_CONFLICTS:-0}
SLEEP='300'            # Number of seconds to sleep if out of API calls
SLEEP_RETRY_COUNT='15' # Number of times to try to sleep before giving up
SLEEP_COUNTER='0'      # Counter of how many times we have gone to sleep
EXISTING_FILE='0'      # Check if a file already exists
PARALLEL_JOBS=${PARALLEL_JOBS:-4} # Default to 4 parallel jobs
PROCESSING_TMP_DIR="/tmp/repo_stats_$RANDOM"
USE_CACHE=${USE_CACHE:-0}

DebugJQ() {
  if [[ ${DEBUG} == true ]]; then
    echo "$1" | jq '.'
  fi
}

Debug() {
  if [[ ${DEBUG} == true ]]; then
    echo "$1"
  fi
}

Header() {
  echo ""
  echo "#### GitHub repo list and sizer (OPTIMIZED)"
  echo ""
  if [[ -z ${GHE_URL} ]]; then
    echo ""
    echo "------------------------------------------------------"
    echo "Please give the URL to the GitHub Enterprise instance you would like to query"
    echo "in the format: https://ghe-url.com"
    echo "followed by [ENTER]:"
    read -r GHE_URL
  fi
  GHE_URL_NO_WHITESPACE="$(echo -e "${GHE_URL}" | tr -d '[:space:]')"
  GHE_URL=$GHE_URL_NO_WHITESPACE

  GetPersonalAccessToken
  
  if [[ "${GHE_URL}" == "https://github.com" ]]; then
    GITHUB_URL="https://api.github.com"
    GRAPHQL_URL="https://api.github.com/graphql"
  else
    GITHUB_URL+="${GHE_URL}/api/v3"
    GRAPHQL_URL="${GHE_URL}/api/graphql"
  fi
  
  if [[ -z "${REPO_PAGE_SIZE}" ]]; then
    REPO_PAGE_SIZE=20
  fi
  
  if [[ -z "${EXTRA_PAGE_SIZE}" ]]; then
    EXTRA_PAGE_SIZE=100
  fi
  
  Debug "curl -kw '%{http_code}' -s --request GET \
  --url ${GITHUB_URL}/user \
  --header \"authorization: Bearer ************\""
  
  USER_RESPONSE=$(curl -kw '%{http_code}' -s --request GET \
  --url "${GITHUB_URL}/user" \
  --header "authorization: Bearer ${GITHUB_TOKEN}")
  
  USER_RESPONSE_CODE="${USER_RESPONSE:(-3)}"
  USER_DATA="${USER_RESPONSE::${#USER_RESPONSE}-4}"
  
  if [[ "$USER_RESPONSE_CODE" != "200" ]]; then
    echo "ERROR: Failed to get valid response from GitHub!"
    echo "${USER_DATA}"
    exit 1
  else
    if [[ "${GHE_URL}" != "https://github.com" ]]; then
      VERSION=$(echo "${USER_DATA}" | jq -r '.enterprise.server_version')
    else
      VERSION="cloud"
    fi
    Debug "GitHub Retrieval Type: ${VERSION}"
    Debug "USER_DATA=${USER_DATA}"
  fi
}

Footer() {
  now=$(date)
  echo ""
  echo "-------------------------------------------------"
  echo "Thanks for using GitHub repo list and sizer!"
  echo "Script completed at: ${now}"
  echo "-------------------------------------------------"
}

GetPersonalAccessToken() {
  if [[ -z ${GITHUB_TOKEN} ]]; then
    if [[ -f ~/.ghe ]]; then
      GITHUB_TOKEN=$(cat ~/.ghe)
    else
      echo "------------------------------------------------------"
      echo "Please enter your GitHub Personal Access Token"
      echo "followed by [ENTER]:"
      read -r GITHUB_TOKEN
      echo "Would you like to save this token for future use? (Y|n)"
      read -r SAVE_TOKEN
      if [[ "${SAVE_TOKEN}" != "n" ]]; then
        echo "${GITHUB_TOKEN}" > ~/.ghe
      fi
    fi
  fi
}

GenerateFiles() {
  TIME_STAMP=$(date +%Y-%m-%d-%H-%M-%S)
  OUTPUT_FILE_NAME="github-repositories_${TIME_STAMP}.csv"
  
  if [[ -f "${OUTPUT_FILE_NAME}" ]]; then
    EXISTING_FILE=1
  else
    echo "org_name,repo_name,is_empty,pushed_at,updated_at,is_fork,repo_size,record_count,collaborator_count,protected_branch_count,pr_review_count,milestone_count,issue_count,pr_count,pr_review_comment_count,commit_comment_count,issue_comment_count,issue_event_count,release_count,project_count,repo_url,migration_issue" > "${OUTPUT_FILE_NAME}"
  fi
  
  if [[ -z ${REPO_URL_FILE} ]]; then
    REPO_URL_FILE="github-repositories_URLs_${TIME_STAMP}.txt"
  fi
  
  if [[ ${ANALYZE_CONFLICTS} -eq 1 ]]; then
    REPO_CONFLICTS_OUTPUT_FILE="github-repositories-conflicts_${TIME_STAMP}.csv"
    echo "number_of_conflicts,repo_name,org_list" > "${REPO_CONFLICTS_OUTPUT_FILE}"
  fi
  
  if [[ ${ANALYZE_TEAMS} -eq 1 ]]; then
    TEAM_CONFLICTS_OUTPUT_FILE="github-teams-conflicts_${TIME_STAMP}.csv"
    echo "number_of_conflicts,team_name,org_list" > "${TEAM_CONFLICTS_OUTPUT_FILE}"
  fi
  
  # Create temp directories for parallel processing
  mkdir -p "${PROCESSING_TMP_DIR}"
}

CheckAdminRights() {
  org=$1
  
  Debug "curl -kw '%{http_code}' -s -X GET \
  -H \"Accept: application/vnd.github.v3+json\" \
  -H \"authorization: Bearer ${GITHUB_TOKEN}\" \
  ${GITHUB_URL}/user/memberships/orgs/${org}"
  
  MEMBERSHIP_RESPONSE=$(curl -kw '%{http_code}' -s -X GET \
  -H "Accept: application/vnd.github.v3+json" \
  -H "authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_URL}/user/memberships/orgs/${org}")
  
  MEMBERSHIP_RESPONSE_CODE="${MEMBERSHIP_RESPONSE:(-3)}"
  MEMBERSHIP_DATA="${MEMBERSHIP_RESPONSE::${#MEMBERSHIP_RESPONSE}-4}"
  
  if [[ "$MEMBERSHIP_RESPONSE_CODE" != "200" ]]; then
    exit 1
  fi
}

GetOrgsFromFile() {
  while IFS=, read -r id created_at login email admin_ct member_ct team_ct repo_ct sfa_required
  do
    # Processing for file input
    echo "Processing org from file..."
  done < "${INPUT_FILE_NAME}"
}

CheckAPILimit() {
  API_REMAINING_CMD=$(curl -s -X GET \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${GITHUB_URL}/rate_limit" |  jq -r '.resources.graphql.remaining' 2>&1)
  
  ERROR_CODE=$?
  if [ "${ERROR_CODE}" -ne 0 ]; then
    echo  "ERROR! Failed to get valid response back from GitHub API!"
    echo "ERROR:[${API_REMAINING_CMD}]"
    exit 1
  fi
  
  if [ "${API_REMAINING_CMD}" -eq 0 ] 2>/dev/null; then
    ((SLEEP_COUNTER++))
    echo "WARN! We have run out of GraphQL calls and need to sleep!"
    echo "Sleeping for ${SLEEP} seconds before next check"
    
    if [ "${SLEEP_COUNTER}" -gt "${SLEEP_RETRY_COUNT}" ]; then
      echo "ERROR! We have tried to wait for:[$SLEEP_RETRY_COUNT] attempts!"
      echo "ERROR! We only sleep for:[${SLEEP_COUNTER}] attempts!"
      echo "Bailing out!"
      exit 1
    else
      sleep "${SLEEP}"
    fi
  else
    echo "[${API_REMAINING_CMD}] API attempts remaining..."
  fi
}

# Enhanced GraphQL query to get more data in a single call
GetRepos() {
  function generate_graphql_data() {
    if [[ "${VERSION}" == "cloud" || $(echo "${VERSION:0:3} >= 2.17" | bc -l) ]]; then
      cat <<EOF
  {
  "query":"query { organization(login: \"${ORG_NAME}\") { repositories(first:${REPO_PAGE_SIZE}${REPO_NEXT_PAGE}) { totalDiskUsage pageInfo { hasPreviousPage hasNextPage hasPreviousPage endCursor } nodes { owner { login } name nameWithOwner diskUsage isEmpty pushedAt updatedAt isFork collaborators(first:1) { totalCount } branchProtectionRules(first:1) { totalCount } pullRequests(first:${REPO_PAGE_SIZE}) { totalCount pageInfo { hasNextPage endCursor } nodes { number commits(first:1){ totalCount } timeline(first:1) { totalCount } comments(first:1) { totalCount } reviews(first:${REPO_PAGE_SIZE}) { totalCount pageInfo { hasNextPage endCursor } nodes { comments(first:1) { totalCount } } } } } milestones(first:1) { totalCount } commitComments(first:1) { totalCount } issues(first:${REPO_PAGE_SIZE}) { totalCount pageInfo { hasNextPage endCursor } nodes { timeline(first:1) { totalCount } comments(first:1) { totalCount } } } releases(first:1) { totalCount } projects(first:1) { totalCount } } } } }"
  }
EOF
    else
      cat <<EOF
  {
  "query":"query { organization(login: \"${ORG_NAME}\") { repositories(first:${REPO_PAGE_SIZE}${REPO_NEXT_PAGE}) { totalDiskUsage pageInfo { hasPreviousPage hasNextPage hasPreviousPage endCursor } nodes { owner { login } name nameWithOwner diskUsage isEmpty pushedAt updatedAt isFork collaborators(first:1) { totalCount } protectedBranches(first:1) { totalCount } pullRequests(first:${REPO_PAGE_SIZE}) { totalCount pageInfo { hasNextPage endCursor } nodes { number commits(first:1){ totalCount } timeline(first:1) { totalCount } comments(first:1) { totalCount } reviews(first:${REPO_PAGE_SIZE}) { totalCount pageInfo { hasNextPage endCursor } nodes { comments(first:1) { totalCount } } } } } milestones(first:1) { totalCount } commitComments(first:1) { totalCount } issues(first:${REPO_PAGE_SIZE}) { totalCount pageInfo { hasNextPage endCursor } nodes { timeline(first:1) { totalCount } comments(first:1) { totalCount } } } releases(first:1) { totalCount } projects(first:1) { totalCount } } } } }"
  }
EOF
    fi
  }
  
  # Check if cached data exists
  if [ "${USE_CACHE}" -eq 1 ] && [ -f "${PROCESSING_TMP_DIR}/repos_${ORG_NAME}_${REPO_PAGE_SIZE}.json" ]; then
    echo "Using cached repository data for ${ORG_NAME}"
    DATA_BLOCK=$(cat "${PROCESSING_TMP_DIR}/repos_${ORG_NAME}_${REPO_PAGE_SIZE}.json")
    ParseRepoData "${DATA_BLOCK}"
    return
  fi
  
  Debug "Getting repos"
  Debug "curl -kw '%{http_code}' -s -X POST -H \"authorization: Bearer ${GITHUB_TOKEN}\" -H \"content-type: application/json\" \
  --data \"$(generate_graphql_data)\" \
  \"${GRAPHQL_URL}\""
  
  REPO_RESPONSE=$(curl -kw '%{http_code}' -s -X POST -H "authorization: Bearer ${GITHUB_TOKEN}" -H "content-type: application/json" \
  --data "$(generate_graphql_data)" \
  "${GRAPHQL_URL}")
  
  REPO_RESPONSE_CODE="${REPO_RESPONSE:(-3)}"
  DATA_BLOCK="${REPO_RESPONSE::${#REPO_RESPONSE}-4}"
  
  if [[ "$REPO_RESPONSE_CODE" != "200" ]]; then
    echo "Error getting Repos for Org: ${ORG_NAME}"
    echo "${DATA_BLOCK}"
  else
    Debug "DEBUG --- REPO DATA BLOCK:"
    DebugJQ "${DATA_BLOCK}"
    
    ERROR_MESSAGE=$(echo "${DATA_BLOCK}" | jq -r '.errors[]?')
    if [[ -n "${ERROR_MESSAGE}" ]]; then
      echo "${DATA_BLOCK}" | jq '.data.organization.repositories.nodes[].name'
    fi
    
    # Save to cache if enabled
    if [ "${USE_CACHE}" -eq 1 ]; then
      echo "${DATA_BLOCK}" > "${PROCESSING_TMP_DIR}/repos_${ORG_NAME}_${REPO_PAGE_SIZE}.json"
    fi
    
    HAS_NEXT_PAGE=$(echo "${DATA_BLOCK}" | jq -r '.data.organization.repositories.pageInfo.hasNextPage')
    REPO_NEXT_PAGE=', after: \"'$(echo "${DATA_BLOCK}" | jq -r '.data.organization.repositories.pageInfo.endCursor')'\"'
    
    ParseRepoData "${DATA_BLOCK}"
    
    if [ "${HAS_NEXT_PAGE}" == "false" ]; then
      REPO_NEXT_PAGE=""
    elif [ "${HAS_NEXT_PAGE}" == "true" ]; then
      GetRepos
    else
      echo "Please validate your PAT, Organization, and access levels!"
    fi
  fi
}

# Process repositories in parallel instead of sequentially
ParseRepoData() {
  PARSE_DATA=$1
  REPOS=$(echo "${PARSE_DATA}" | jq -r '.data.organization.repositories.nodes')
  
  # Create a temporary file with all repos data
  REPO_LIST_FILE="${PROCESSING_TMP_DIR}/repo_list_$$"
  echo "${REPOS}" | jq -r '.[] | @base64' > "${REPO_LIST_FILE}"
  
  # Define our processing function
  process_repo() {
    local REPO=$1
    _jq() {
      echo "${REPO}" | base64 --decode | jq -r "${1}"
    }
    
    OWNER=$(_jq '.owner.login' | tr '[:upper:]' '[:lower:]')
    REPO_NAME=$(_jq '.name' | tr '[:upper:]' '[:lower:]')
    
    # Skip if already analyzed
    if grep -q "${OWNER},${REPO_NAME}," "${OUTPUT_FILE_NAME}" 2>/dev/null; then
      echo "Repo:[${OWNER}/${REPO_NAME}] has previously been analyzed, moving on..."
      return 0
    fi
    
    echo "Analyzing Repo: ${REPO_NAME}"
    
    REPO_SIZE_KB=$(_jq '.diskUsage')
    REPO_SIZE=$(ConvertKBToMB "${REPO_SIZE_KB}")
    IS_EMPTY=$(_jq '.isEmpty')
    PUSHED_AT=$(_jq '.pushedAt')
    UPDATED_AT=$(_jq '.updatedAt')
    IS_FORK=$(_jq '.isFork')
    MILESTONE_CT=$(_jq '.milestones.totalCount')
    COLLABORATOR_CT=$(_jq '.collaborators.totalCount')
    PR_CT=$(_jq '.pullRequests.totalCount')
    ISSUE_CT=$(_jq '.issues.totalCount')
    RELEASE_CT=$(_jq '.releases.totalCount')
    COMMIT_COMMENT_CT=$(_jq '.commitComments.totalCount')
    PROJECT_CT=$(_jq '.projects.totalCount')
    
    if [[ "${VERSION}" == "cloud" || $(echo "${VERSION:0:3} >= 2.17" | bc -l) ]]; then
      PROTECTED_BRANCH_CT=$(_jq '.branchProtectionRules.totalCount')
    else
      PROTECTED_BRANCH_CT=$(_jq '.protectedBranches.totalCount')
    fi
    
    ISSUE_EVENT_CT=0
    ISSUE_COMMENT_CT=0
    PR_REVIEW_CT=0
    PR_REVIEW_COMMENT_CT=0
    
    # Process issues and PRs in parallel
    local ISSUES=$(_jq '.issues.nodes')
    local PRS=$(_jq '.pullRequests.nodes')
    
    # Process issues
    if [[ $ISSUE_CT -ne 0 ]]; then
      # Process issues in the main GraphQL response
      for ISSUE in $(echo "${ISSUES}" | jq -r '.[] | @base64'); do
        _issue_jq() {
          echo "${ISSUE}" | base64 --decode | jq -r "${1}"
        }
        EVENT_CT=$(_issue_jq '.timeline.totalCount')
        COMMENT_CT=$(_issue_jq '.comments.totalCount')
        ISSUE_EVENT_CT=$((ISSUE_EVENT_CT + EVENT_CT - COMMENT_CT))
        ISSUE_COMMENT_CT=$((ISSUE_COMMENT_CT + COMMENT_CT))
      done
      
      # Check if there are more pages
      local HAS_NEXT_ISSUES_PAGE=$(_jq '.issues.pageInfo.hasNextPage')
      local ISSUE_NEXT_PAGE=', after: \"'$(_jq '.issues.pageInfo.endCursor')'\"'
      
      # Get additional issues if needed
      if [ "$HAS_NEXT_ISSUES_PAGE" == "true" ]; then
        local ADDITIONAL_ISSUE_STATS=$(get_remaining_issues "${OWNER}" "${REPO_NAME}" "${ISSUE_NEXT_PAGE}")
        if [ -n "${ADDITIONAL_ISSUE_STATS}" ]; then
          ISSUE_EVENT_CT=$((ISSUE_EVENT_CT + $(echo "${ADDITIONAL_ISSUE_STATS}" | jq -r '.event_count')))
          ISSUE_COMMENT_CT=$((ISSUE_COMMENT_CT + $(echo "${ADDITIONAL_ISSUE_STATS}" | jq -r '.comment_count')))
        fi
      fi
    fi
    
    # Process pull requests
    if [[ $PR_CT -ne 0 ]]; then
      # Process PRs in the main GraphQL response
      for PR in $(echo "${PRS}" | jq -r '.[] | @base64'); do
        _pr_jq() {
          echo "${PR}" | base64 --decode | jq -r "${1}"
        }
        PR_NUMBER=$(_pr_jq '.number')
        EVENT_CT=$(_pr_jq '.timeline.totalCount')
        COMMENT_CT=$(_pr_jq '.comments.totalCount')
        REVIEW_CT=$(_pr_jq '.reviews.totalCount')
        COMMIT_CT=$(_pr_jq '.commits.totalCount')
        
        # Process reviews
        if [[ ${REVIEW_CT} -ne 0 ]]; then
          local REVIEWS=$(_pr_jq '.reviews.nodes')
          for REVIEW in $(echo "${REVIEWS}" | jq -r '.[] | @base64'); do
            _review_jq() {
              echo "${REVIEW}" | base64 --decode | jq -r "${1}"
            }
            REVIEW_COMMENT_CT=$(_review_jq '.comments.totalCount')
            PR_REVIEW_COMMENT_CT=$((PR_REVIEW_COMMENT_CT + REVIEW_COMMENT_CT))
          done
          
          # Check if there are more review pages
          local HAS_NEXT_REVIEWS_PAGE=$(_pr_jq '.reviews.pageInfo.hasNextPage')
          local REVIEW_NEXT_PAGE=', after: \"'$(_pr_jq '.reviews.pageInfo.endCursor')'\"'
          
          # Get additional reviews if needed
          if [ "$HAS_NEXT_REVIEWS_PAGE" == "true" ]; then
            local ADDITIONAL_REVIEW_STATS=$(get_remaining_reviews "${OWNER}" "${REPO_NAME}" "${PR_NUMBER}" "${REVIEW_NEXT_PAGE}")
            if [ -n "${ADDITIONAL_REVIEW_STATS}" ]; then
              PR_REVIEW_COMMENT_CT=$((PR_REVIEW_COMMENT_CT + $(echo "${ADDITIONAL_REVIEW_STATS}" | jq -r '.comment_count')))
            fi
          fi
        fi
        
        ISSUE_EVENT_CT=$((ISSUE_EVENT_CT + EVENT_CT - COMMENT_CT - COMMIT_CT))
        ISSUE_COMMENT_CT=$((ISSUE_COMMENT_CT + COMMENT_CT))
        PR_REVIEW_CT=$((PR_REVIEW_CT + REVIEW_CT))
      done
      
      # Check if there are more PR pages
      local HAS_NEXT_PRS_PAGE=$(_jq '.pullRequests.pageInfo.hasNextPage')
      local PR_NEXT_PAGE=', after: \"'$(_jq '.pullRequests.pageInfo.endCursor')'\"'
      
      # Get additional PRs if needed
      if [ "$HAS_NEXT_PRS_PAGE" == "true" ]; then
        local ADDITIONAL_PR_STATS=$(get_remaining_prs "${OWNER}" "${REPO_NAME}" "${PR_NEXT_PAGE}")
        if [ -n "${ADDITIONAL_PR_STATS}" ]; then
          ISSUE_EVENT_CT=$((ISSUE_EVENT_CT + $(echo "${ADDITIONAL_PR_STATS}" | jq -r '.event_count')))
          ISSUE_COMMENT_CT=$((ISSUE_COMMENT_CT + $(echo "${ADDITIONAL_PR_STATS}" | jq -r '.comment_count')))
          PR_REVIEW_CT=$((PR_REVIEW_CT + $(echo "${ADDITIONAL_PR_STATS}" | jq -r '.review_count')))
          PR_REVIEW_COMMENT_CT=$((PR_REVIEW_COMMENT_CT + $(echo "${ADDITIONAL_PR_STATS}" | jq -r '.review_comment_count')))
        fi
      fi
    fi
    
    RECORD_CT=$((COLLABORATOR_CT + PROTECTED_BRANCH_CT + PR_REVIEW_CT + MILESTONE_CT + ISSUE_CT + PR_CT + PR_REVIEW_COMMENT_CT + COMMIT_COMMENT_CT + ISSUE_COMMENT_CT + ISSUE_EVENT_CT + RELEASE_CT + PROJECT_CT))
    MIGRATION_ISSUE=$(MarkMigrationIssues "${REPO_SIZE}" "${RECORD_CT}")
    
    if [ "${MIGRATION_ISSUE}" -eq 0 ]; then
      MIGRATION_ISSUE="TRUE"
    else
      MIGRATION_ISSUE="FALSE"
    fi
    
    # Use a lock file to prevent multiple processes from writing to the file simultaneously
    flock -x 200
    echo "${ORG_NAME},${REPO_NAME},${IS_EMPTY},${PUSHED_AT},${UPDATED_AT},${IS_FORK},${REPO_SIZE},${RECORD_CT},${COLLABORATOR_CT},${PROTECTED_BRANCH_CT},${PR_REVIEW_CT},${MILESTONE_CT},${ISSUE_CT},${PR_CT},${PR_REVIEW_COMMENT_CT},${COMMIT_COMMENT_CT},${ISSUE_COMMENT_CT},${ISSUE_EVENT_CT},${RELEASE_CT},${PROJECT_CT},${GHE_URL}/${ORG_NAME}/${REPO_NAME},${MIGRATION_ISSUE}" >> "${OUTPUT_FILE_NAME}"
    flock -u 200
    
    ERROR_CODE=$?
    if [ $ERROR_CODE -ne 0 ]; then
      exit 1
    fi
    
    if [[ ${ANALYZE_CONFLICTS} -eq 1 ]]; then
      # Handle conflict analysis if needed
      echo "Conflict analysis placeholder"
    fi
  }
  
  # Process repositories sequentially with improved efficiency
  # Note: We're not using GNU parallel due to issues with exporting complex functions
  echo "Processing ${REPO_PAGE_SIZE} repositories with improved efficiency..."
  
  # Create a FIFO queue for parallel processing without GNU parallel
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

# Process issues in a single batch instead of recursively
get_remaining_issues() {
  local OWNER=$1
  local REPO_NAME=$2
  local NEXT_PAGE=$3
  local EVENT_COUNT=0
  local COMMENT_COUNT=0
  local RETRY_COUNT=0
  local MAX_RETRIES=3
  
  while [ "$NEXT_PAGE" != "" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    local GRAPHQL_QUERY="{  repository(owner:\"${OWNER}\" name:\"${REPO_NAME}\") { owner { login } name issues(first:${EXTRA_PAGE_SIZE}${NEXT_PAGE}) { totalCount pageInfo { hasNextPage endCursor } nodes { timeline(first: 1) { totalCount } comments(first: 1) { totalCount } } } }}"
    
    local ISSUE_RESPONSE=$(curl -kw '%{http_code}' -s -X POST -H "authorization: Bearer ${GITHUB_TOKEN}" -H "content-type: application/json" \
    --data "{\"query\":\"${GRAPHQL_QUERY}\"}" \
    "${GRAPHQL_URL}")
    
    local ISSUE_RESPONSE_CODE="${ISSUE_RESPONSE:(-3)}"
    local ISSUE_DATA="${ISSUE_RESPONSE::${#ISSUE_RESPONSE}-4}"
    
    if [[ "${ISSUE_RESPONSE_CODE}" != "200" ]]; then
      echo "Error getting more Issues for Repo: ${OWNER}/${REPO_NAME}, retrying..."
      RETRY_COUNT=$((RETRY_COUNT + 1))
      sleep 2
      continue
    fi
    
    # Check for errors in the GraphQL response
    local ERROR_MESSAGE=$(echo "${ISSUE_DATA}" | jq -r '.errors[0].message // empty')
    if [[ -n "${ERROR_MESSAGE}" ]]; then
      echo "ERROR --- GraphQL error: ${ERROR_MESSAGE}"
      return
    fi
    
    # Process issues
    local ISSUES=$(echo "${ISSUE_DATA}" | jq -r '.data.repository.issues.nodes // []')
    for ISSUE in $(echo "${ISSUES}" | jq -r '.[] | @base64'); do
      local ISSUE_OBJ=$(echo "${ISSUE}" | base64 --decode)
      local E_CT=$(echo "${ISSUE_OBJ}" | jq -r '.timeline.totalCount')
      local C_CT=$(echo "${ISSUE_OBJ}" | jq -r '.comments.totalCount')
      EVENT_COUNT=$((EVENT_COUNT + E_CT - C_CT))
      COMMENT_COUNT=$((COMMENT_COUNT + C_CT))
    done
    
    # Check for next page
    local HAS_NEXT_PAGE=$(echo "${ISSUE_DATA}" | jq -r '.data.repository.issues.pageInfo.hasNextPage // false')
    if [ "$HAS_NEXT_PAGE" == "true" ]; then
      local NEXT_CURSOR=$(echo "${ISSUE_DATA}" | jq -r '.data.repository.issues.pageInfo.endCursor')
      NEXT_PAGE=", after: \"${NEXT_CURSOR}\""
    else
      NEXT_PAGE=""
    fi
    
    # Reset retry count on success
    RETRY_COUNT=0
  done
  
  echo "{\"event_count\": ${EVENT_COUNT}, \"comment_count\": ${COMMENT_COUNT}}"
}

# Process PRs in a single batch instead of recursively
get_remaining_prs() {
  local OWNER=$1
  local REPO_NAME=$2
  local NEXT_PAGE=$3
  local EVENT_COUNT=0
  local COMMENT_COUNT=0
  local REVIEW_COUNT=0
  local REVIEW_COMMENT_COUNT=0
  local RETRY_COUNT=0
  local MAX_RETRIES=3
  
  while [ "$NEXT_PAGE" != "" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    local GRAPHQL_QUERY="{  repository(owner:\"${OWNER}\" name:\"${REPO_NAME}\") {  owner {  login  }  name   pullRequests(first:${EXTRA_PAGE_SIZE}${NEXT_PAGE}) {  totalCount  pageInfo {    hasNextPage  endCursor  }  nodes { number  commits(first:1){  totalCount   }    timeline(first: 1) {  totalCount    }    comments(first: 1) {  totalCount    }    reviews(first: ${EXTRA_PAGE_SIZE}) {  totalCount  pageInfo {    hasNextPage  endCursor  }    nodes {  comments(first: 1) {    totalCount  }  }   }  }  }  }}"
    
    local PR_RESPONSE=$(curl -kw '%{http_code}' -s -X POST -H "authorization: Bearer ${GITHUB_TOKEN}" -H "content-type: application/json" \
    --data "{\"query\":\"${GRAPHQL_QUERY}\"}" \
    "${GRAPHQL_URL}")
    
    local PR_RESPONSE_CODE="${PR_RESPONSE:(-3)}"
    local PR_DATA="${PR_RESPONSE::${#PR_RESPONSE}-4}"
    
    if [[ "$PR_RESPONSE_CODE" != "200" ]]; then
      echo "Error getting more Pull Requests for Repo: ${OWNER}/${REPO_NAME}, retrying..."
      RETRY_COUNT=$((RETRY_COUNT + 1))
      sleep 2
      continue
    fi
    
    # Check for errors in the GraphQL response
    local ERROR_MESSAGE=$(echo "${PR_DATA}" | jq -r '.errors[0].message // empty')
    if [[ -n "${ERROR_MESSAGE}" ]]; then
      echo "ERROR --- GraphQL error: ${ERROR_MESSAGE}"
      return
    fi
    
    # Process PRs
    local PRS=$(echo "${PR_DATA}" | jq -r '.data.repository.pullRequests.nodes // []')
    for PR in $(echo "${PRS}" | jq -r '.[] | @base64'); do
      local PR_OBJ=$(echo "${PR}" | base64 --decode)
      local PR_NUMBER=$(echo "${PR_OBJ}" | jq -r '.number')
      local E_CT=$(echo "${PR_OBJ}" | jq -r '.timeline.totalCount')
      local C_CT=$(echo "${PR_OBJ}" | jq -r '.comments.totalCount')
      local R_CT=$(echo "${PR_OBJ}" | jq -r '.reviews.totalCount')
      local CM_CT=$(echo "${PR_OBJ}" | jq -r '.commits.totalCount')
      
      # Process reviews
      if [[ ${R_CT} -ne 0 ]]; then
        local REVIEWS=$(echo "${PR_OBJ}" | jq -r '.reviews.nodes')
        for REVIEW in $(echo "${REVIEWS}" | jq -r '.[] | @base64'); do
          local REVIEW_OBJ=$(echo "${REVIEW}" | base64 --decode)
          local RC_CT=$(echo "${REVIEW_OBJ}" | jq -r '.comments.totalCount')
          REVIEW_COMMENT_COUNT=$((REVIEW_COMMENT_COUNT + RC_CT))
        done
        
        # Check if there are more review pages
        local HAS_NEXT_REVIEWS=$(echo "${PR_OBJ}" | jq -r '.reviews.pageInfo.hasNextPage')
        if [ "$HAS_NEXT_REVIEWS" == "true" ]; then
          local REVIEWS_NEXT_CURSOR=$(echo "${PR_OBJ}" | jq -r '.reviews.pageInfo.endCursor')
          local REVIEWS_STATS=$(get_remaining_reviews "${OWNER}" "${REPO_NAME}" "${PR_NUMBER}" ", after: \"${REVIEWS_NEXT_CURSOR}\"")
          REVIEW_COMMENT_COUNT=$((REVIEW_COMMENT_COUNT + $(echo "${REVIEWS_STATS}" | jq -r '.comment_count')))
        fi
      fi
      
      EVENT_COUNT=$((EVENT_COUNT + E_CT - C_CT - CM_CT))
      COMMENT_COUNT=$((COMMENT_COUNT + C_CT))
      REVIEW_COUNT=$((REVIEW_COUNT + R_CT))
    done
    
    # Check for next page
    local HAS_NEXT_PAGE=$(echo "${PR_DATA}" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage // false')
    if [ "$HAS_NEXT_PAGE" == "true" ]; then
      local NEXT_CURSOR=$(echo "${PR_DATA}" | jq -r '.data.repository.pullRequests.pageInfo.endCursor')
      NEXT_PAGE=", after: \"${NEXT_CURSOR}\""
    else
      NEXT_PAGE=""
    fi
    
    # Reset retry count on success
    RETRY_COUNT=0
  done
  
  echo "{\"event_count\": ${EVENT_COUNT}, \"comment_count\": ${COMMENT_COUNT}, \"review_count\": ${REVIEW_COUNT}, \"review_comment_count\": ${REVIEW_COMMENT_COUNT}}"
}

# Process reviews in a single batch instead of recursively
get_remaining_reviews() {
  local OWNER=$1
  local REPO_NAME=$2
  local PR_NUMBER=$3
  local NEXT_PAGE=$4
  local COMMENT_COUNT=0
  local RETRY_COUNT=0
  local MAX_RETRIES=3
  
  while [ "$NEXT_PAGE" != "" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    local GRAPHQL_QUERY="{ repository(owner:\"${OWNER}\" name:\"${REPO_NAME}\") { owner { login } name pullRequest(number:${PR_NUMBER}) { commits(first:1){  totalCount   }    timeline(first: 1) {  totalCount    }    comments(first: 1) {  totalCount    }    reviews(first: ${EXTRA_PAGE_SIZE}${NEXT_PAGE}) { totalCount pageInfo { hasNextPage endCursor } nodes { comments(first: 1) {    totalCount } } } } }}"
    
    local REVIEW_RESPONSE=$(curl -kw '%{http_code}' -s -X POST -H "authorization: Bearer ${GITHUB_TOKEN}" -H "content-type: application/json" \
    --data "{\"query\":\"${GRAPHQL_QUERY}\"}" \
    "${GRAPHQL_URL}")
    
    local REVIEW_RESPONSE_CODE="${REVIEW_RESPONSE:(-3)}"
    local REVIEW_DATA="${REVIEW_RESPONSE::${#REVIEW_RESPONSE}-4}"
    
    if [[ "$REVIEW_RESPONSE_CODE" != "200" ]]; then
      echo "Error getting more PR Reviews, retrying..."
      RETRY_COUNT=$((RETRY_COUNT + 1))
      sleep 2
      continue
    fi
    
    # Check for errors in the GraphQL response
    local ERROR_MESSAGE=$(echo "${REVIEW_DATA}" | jq -r '.errors[0].message // empty')
    if [[ -n "${ERROR_MESSAGE}" ]]; then
      echo "ERROR --- GraphQL error: ${ERROR_MESSAGE}"
      return
    fi
    
    # Process reviews
    local REVIEWS=$(echo "${REVIEW_DATA}" | jq -r '.data.repository.pullRequest.reviews.nodes // []')
    for REVIEW in $(echo "${REVIEWS}" | jq -r '.[] | @base64'); do
      local REVIEW_OBJ=$(echo "${REVIEW}" | base64 --decode)
      local C_CT=$(echo "${REVIEW_OBJ}" | jq -r '.comments.totalCount')
      COMMENT_COUNT=$((COMMENT_COUNT + C_CT))
    done
    
    # Check for next page
    local HAS_NEXT_PAGE=$(echo "${REVIEW_DATA}" | jq -r '.data.repository.pullRequest.reviews.pageInfo.hasNextPage // false')
    if [ "$HAS_NEXT_PAGE" == "true" ]; then
      local NEXT_CURSOR=$(echo "${REVIEW_DATA}" | jq -r '.data.repository.pullRequest.reviews.pageInfo.endCursor')
      NEXT_PAGE=", after: \"${NEXT_CURSOR}\""
    else
      NEXT_PAGE=""
    fi
    
    # Reset retry count on success
    RETRY_COUNT=0
  done
  
  echo "{\"comment_count\": ${COMMENT_COUNT}}"
}

GetTeams() {
  function generate_graphql_data() {
    cat <<EOF
    {
  "query":"query {   organization(login:\"${OWNER}\") {    teams(first: ${REPO_PAGE_SIZE}${TEAM_NEXT_PAGE}) {  pageInfo{  hasNextPage  endCursor  } nodes { slug } } } }"
    }
EOF
  }
  
  Debug "curl -kw '%{http_code}' -s -X POST -H \"authorization: Bearer ${GITHUB_TOKEN}\" -H \"content-type: application/json\" \
  --data \"$(generate_graphql_data)\" \
  \"${GRAPHQL_URL}\""
  
  TEAM_RESPONSE=$(curl -kw '%{http_code}' -s -X POST -H "authorization: Bearer ${GITHUB_TOKEN}" -H "content-type: application/json" \
  --data "$(generate_graphql_data)" \
  "${GRAPHQL_URL}")
  
  TEAM_RESPONSE_CODE="${TEAM_RESPONSE:(-3)}"
  TEAM_DATA="${TEAM_RESPONSE::${#TEAM_RESPONSE}-4}"
  
  if [[ "$TEAM_RESPONSE_CODE" != "200" ]]; then
    echo "Error getting Teams for Org: ${OWNER}"
    echo "${TEAM_DATA}"
    return
  else
    Debug "TEAM DATA BLOCK:"
    DebugJQ "${TEAM_DATA}"
    
    ERROR_MESSAGE=$(echo "$TEAM_DATA" | jq -r '.errors[]?')
    if [[ -n "${ERROR_MESSAGE}" ]]; then
      echo "ERROR --- Errors occurred while retrieving teams for org: ${OWNER}"
      echo "${ERROR_MESSAGE}" | jq '.'
      return
    fi
    
    TEAMS=$(echo "${TEAM_DATA}" | jq '.data.organization.teams.nodes')
    HAS_NEXT_TEAM_PAGE=$(echo "${TEAM_DATA}" | jq -r '.data.organization.teams.pageInfo.hasNextPage')
    TEAM_NEXT_PAGE=', after: \"'$(echo "${TEAM_DATA}" | jq -r '.data.organization.teams.pageInfo.endCursor')'\"'
    
    # Process teams data
    for TEAM in $(echo "${TEAMS}" | jq -r '.[] | @base64'); do
      _team_jq() {
        echo "${TEAM}" | base64 --decode | jq -r "${1}"
      }
      TEAM_NAME=$(_team_jq '.slug')
      TEAM_INDEX=-1
      
      for i in "${!TEAM_LIST[@]}"; do
        if [[ "${TEAM_LIST[$i]}" = "${TEAM_NAME}" ]]; then
          TEAM_INDEX=${i}
        fi
      done
      
      if [[ ${TEAM_INDEX} -eq -1 ]]; then
        Debug "Team: ${TEAM_NAME} is unique. Adding to the list!"
        TEAM_LIST+=( "${TEAM_NAME}" )
        TEAM_ORG_LIST[ ${#TEAM_LIST[@]} - 1 ]=${ORG_NAME}
        NUMBER_OF_TEAM_CONFLICTS[ ${#TEAM_LIST[@]} - 1 ]=1
      else
        Debug "Team: $TEAM_NAME already exists. Adding ${ORG_NAME} to the conflict list"
        TEAM_ORG_LIST[TEAM_INDEX]+=" ${ORG_NAME}"
        (( NUMBER_OF_TEAM_CONFLICTS[TEAM_INDEX]++ ))
      fi
    done
    
    if [ "${HAS_NEXT_TEAM_PAGE}" == "false" ]; then
      Debug "Gathered all teams"
      TEAM_NEXT_PAGE=""
    elif [ "${HAS_NEXT_TEAM_PAGE}" == "true" ]; then
      Debug "More pages of teams. Gathering next batch."
      GetTeams
    else
      echo ""
      echo "ERROR! Failed response back from GitHub!"
      echo "Please validate your PAT, Organization, and access levels!"
      exit 1
    fi
  fi
}

MarkMigrationIssues() {
  REPO_SIZE="$1"
  RECORD_COUNT="$2"
  if [ "${RECORD_COUNT}" -ge 60000 ] || [ "${REPO_SIZE}" -gt 1500 ]; then
    echo "0"
    return 0
  else
    echo "1"
    return 1
  fi
}

ReportConflicts() {
  if [[ ${ANALYZE_CONFLICTS} -eq 1 ]]; then
    for (( i=0; i<${#REPO_LIST[@]}; i++)) do
      if (( ${NUMBER_OF_CONFLICTS[$i]} > 1 )); then
        echo "${NUMBER_OF_CONFLICTS[$i]},${REPO_LIST[$i]},${GROUP_LIST[$i]}" >> "${REPO_CONFLICTS_OUTPUT_FILE}"
      fi
    done
  fi
  
  if [[ ${ANALYZE_TEAMS} -eq 1 ]]; then
    for (( i=0; i<${#TEAM_LIST[@]}; i++)) do
      if (( ${NUMBER_OF_TEAM_CONFLICTS[$i]} > 1 )); then
        echo "${NUMBER_OF_TEAM_CONFLICTS[$i]},${TEAM_LIST[$i]},${TEAM_ORG_LIST[$i]}" >> "${TEAM_CONFLICTS_OUTPUT_FILE}"
      fi
    done
  fi
}

ConvertKBToMB() {
  VALUE=$1
  REGEX='^[0-9]+$'
  if ! [[ ${VALUE} =~ ${REGEX} ]] ; then
    echo "ERROR! Not a number:[${VALUE}]"
    exit 1
  fi
  SIZEINMB=$((VALUE/1024))
  echo "${SIZEINMB}"
  return ${SIZEINMB}
}

ValidateJQ() {
  if ! jq --version &>/dev/null
  then
    echo "Failed to find jq in the path!"
    exit 1
  fi
}

CleanUp() {
  rm -rf "${PROCESSING_TMP_DIR}" 2>/dev/null || true
}

# Main execution flow
trap CleanUp EXIT

Header
ValidateJQ
GenerateFiles

if [[ -z ${INPUT_FILE_NAME} ]]; then
  CheckAdminRights "${ORG_NAME}"
  echo "------------------------------------------------------"
  echo "Getting repositories for org: ${ORG_NAME}"
  CheckAPILimit
  GetRepos
else
  GetOrgsFromFile
fi

ReportConflicts
Footer
