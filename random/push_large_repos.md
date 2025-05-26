In a single push no more than 2GB of data can be pushed to github.com even if the individual blob objects are smaller than the maximum object size (usually 100MB). Consequently, repositories that are larger than 2GB cannot be pushed to github.com. This can be an issue if a repository with a large amount of history is migrated from another VCS to github.com.

The solution to this problem is to push the repository in chunks of less than 2GB. That means pushing you would push the first 2 years, then the next 2 years etc. to github.com. However, finding the time ranges can be cumbersome. Finding these ranges can be in particular difficult if the repository has multiple root commits (because of a merge of two projects in the past).

Consider this

```text
HEAD -> A
        |\
        B C
        | |
        D E
```

You might push `D`, then `B`, and finally `A`. But pushing `A` might still fail if `C` and `E` reference data greater than 2GB. Therefore, you need to push `E` and `C` *before* you can successfully push `A`.

The following script will push your repository in 2GB chunks and should handle all these edge cases:

```bash
#!/bin/bash

################################################################################
########################## chunked-push.sh #####################################
################################################################################

# LEGEND:
# Repositories larger than 2GB cannot be pushed to github.com
#
# This script attempts to push one branch from such a repository in
# chunks smaller than 2GB. Make sure to use SSH as push protocol as
# HTTPS frequently runs into trouble with these large pushes.
#
# Run this script within the repository and pass the name of the
# remote as first argument.
#
# The script creates some temporary local and remote references with names like
#
#     refs/github-sevices/chunked-upload/*
#
# If it completes successfully, it will clean up those references.
#
# Example: chunked-push.sh origin
#
########################
# Set to exit on error #
########################
set -e

# DRY_RUN can be set (either by uncommenting the following line or by
# setting it via the environment) to test this script without doing
# any any actual pushes.
# DRY_RUN=1

# MAX_PUSH_SIZE is the maximum estimated size of a push that will be
# attempted. Note that this is only an estimate, so it should probably
# be set smaller than any hard limits. However, even if it is too big,
# the script should succeed (though that makes it more likely that
# pushes will fail and have to be retried).

########
# VARS #
########
# Default max push size is 1GB
MAX_PUSH_SIZE="${MAX_PUSH_SIZE:-1000000000}"
# Remote to push towards, default origin
REMOTE="${1:-origin}"
# Prefix for temorary refs created
REF_PREFIX='refs/github-services/chunked-upload'
# Tip commit of the current branch that we want to push to GitHub
HEAD="$(git rev-parse --verify HEAD)"
# Name of the current branch that we want to push to GitHub
BRANCH="$(git symbolic-ref --short HEAD)"
# Options to push
PUSH_OPTS="--no-follow-tags"

################################################################################
########################## FUNCTIONS BELOW #####################################
################################################################################
################################################################################
#### Function Header ###########################################################
Header() {
  echo ""
  echo "-------------------------------"
  echo "-- Push repository in chunks --"
  echo "-------------------------------"
  echo ""
  echo "Gathering information from local repository..."
}
################################################################################
#### Function Git_Push #########################################################
Git_Push() {
  if test -n "${DRY_RUN}"; then
    # Just show what push command would be run, without actually
    # running it:
    echo git push "$@"
  else
    git push "$@"
  fi
}
################################################################################
#### Function Estimate_Size ####################################################
Estimate_Size() {
  # usage: Estimate_Size [REV]
  #
  # Return the estimated total on-disk size of all unpushed objects that
  # are reachable from REV (or ${HEAD}, if REV is not specified).
  local REV=''
  REV="${1:-$HEAD}"

  git for-each-ref --format='^%(objectname)' "${REF_PREFIX}" |
    git rev-list --objects "${REV}" --stdin |
    awk '{print $1}' |
    git cat-file --batch-check='%(objectsize:disk)' |
    awk 'BEGIN {sum = 0} {sum += $1} END {print sum}'
}
################################################################################
#### Function Check_Size #######################################################
Check_Size() {
  # usage: Check_Size [REV]
  #
  # Check whether a push of REV (or ${HEAD}, if REV is not specified) is
  # estimated to be within $MAX_PUSH_SIZE.
  local REV=''
  REV="${1:-$HEAD}"
  local SIZE=''
  SIZE="$(Estimate_Size "${REV}")"

  if test "${SIZE}" -gt "${MAX_PUSH_SIZE}"; then
    echo >&2 "size of push is predicted to be too large: ${SIZE} bytes"
    return 1
  else
    echo >&2 "predicted push size: ${SIZE} bytes"
  fi
}
################################################################################
#### Function Push_Branch ######################################################
Push_Branch() {
  # usage: Push_Branch
  #
  # Check whether a push of ${BRANCH} to ${REMOTE} is likely to be within
  # $MAX_PUSH_SIZE. If so, try to push it. If not, emit an informational
  # message and return an error.
  Check_Size &&
  Git_Push ${PUSH_OPTS} --force "${REMOTE}" "${HEAD}:refs/heads/${BRANCH}"
}
################################################################################
#### Function Push_Rev #########################################################
Push_Rev() {
  # usage: Push_Branch REV
  #
  # Check whether a push of REV to ${REMOTE} is likely to be within
  # $MAX_PUSH_SIZE. If so, try to push it to a temporary reference. If
  # not, emit an informational message and return an error.
  local REV="$1"

  Check_Size "${REV}" &&
  Git_Push ${PUSH_OPTS} --force "${REMOTE}" "${REV}:${REF_PREFIX}/${REV}"
}
################################################################################
#### Function Push_Chunk #######################################################
Push_Chunk() {
  # usage: Push_Chunk
  #
  # Try to push a portion of the contents of ${HEAD}, such that the amount
  # to be pushed is estimated to be less than $MAX_PUSH_SIZE. This is
  # done using the same algorithm as 'git bisect'; namely, by
  # successively halving of the number of commits until the size of the
  # commits to be pushed is less than $MAX_PUSH_SIZE. For simplicity and
  # to avoid extra estimation work, instead of trying to find the
  # optimum number of commits to push, we stop as soon as we find a
  # range that meets the criterion. This will typically result in a push
  # with a size approximately in the range
  #
  #     $MAX_PUSH_SIZE / 2 <= size <= $MAX_PUSH_SIZE
  CHUNK_SIZE="${HEAD}"
  LAST_REV=''

  while true; do
    # find a new midpoint, this call sets ${bisect_rev} and $bisect_steps
    # Note: $bisect_rev and $bisect_steps are ENV vars and need to be lower case
    eval "$(
      git for-each-ref --format='^%(objectname)' "${REF_PREFIX}" |
        git rev-list --bisect-vars "${CHUNK_SIZE}" --stdin
    )"

    # Check to see if we have hit the bottom and cant get smaller
    if [ "${bisect_rev}" == "${LAST_REV}" ] && [ -n "${bisect_rev}" ] && [ -n "${LAST_REV}" ]; then
      # ERROR
      echo >&2 "We have hit the smallest commit:[${bisect_rev}] and its larger than allowed upload size!"
      exit 1
    fi

    # Try to push the bisect rev
    echo >&2 "attempting to push:[${bisect_rev}]..."
    if Push_Rev "${bisect_rev}"; then
      # Success
      echo >&2 "push succeeded!"
      git update-ref "${REF_PREFIX}/${bisect_rev}" "${bisect_rev}"
      return
    else
      # Failure
      echo >&2 "push failed; trying a smaller chunk"
      # Set the local vars
      CHUNK_SIZE="${bisect_rev}"
      LAST_REV="${bisect_rev}"
    fi
  done
}
################################################################################
############################### MAIN ###########################################
################################################################################

##########
# Header #
##########
Header

############################
# Start to push the chunks #
############################
while ! Push_Branch ; do
  echo >&2 "trying a partial push"
  Push_Chunk
done

###########################################
# Clean up the local temporary references #
###########################################
git for-each-ref --format='delete %(refname)' "${REF_PREFIX}" |
  git update-ref --stdin

############################################
# Clean up the remote temporary references #
############################################
Git_Push ${PUSH_OPTS} --prune "${REMOTE}" "${REF_PREFIX}/*:${REF_PREFIX}/*"
```

Once you have pushed the `main` branch of your code to **GitHub**, you may try to run a `git push --all` to grab any other *local* branches you have, and push them to the remote location.
If you are pushing a **very large** repository with *hundreds* or *thousands* of branches, you may notice the command will hang and fail. You will likely need to use the following script to push all your branches individually.

```bash
#!/bin/bash

################################################################################
##################### Push Local Branches individually #########################
################################################################################

# Legend:
# This script should be run from inside the local repository
# It will get a list of all local branches, checkout the individual branch,
# and push it to the remote.

########
# VARS #
########
MAIN_BRANCH="master" # Default branch main or master usually
BRANCH_LIST=()       # List of all branches found in repository locally
BRANCH_COUNT=0       # Count of branches pushed to remote
TOTAL_BRANCHES=0     # Total count of branches found
COUNTER=0            # Current branch were pushing
ERROR_COUNT=0        # Count of all failed pushes

##########
# Header #
##########
echo ""
echo "-----------------------------------------"
echo "Push Local Branches individually to remote"
echo "-----------------------------------------"
echo ""
echo "-----------------------------------------"
echo "Main branch set to:[${MAIN_BRANCH}]"
echo "-----------------------------------------"
echo ""

####################################################
# Check to see we are on the main or master branch #
####################################################
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
if [ "${BRANCH_NAME}" != "${MAIN_BRANCH}" ]; then
  # Error
  echo "ERROR! You need to currently have checked out the branch:[$MAIN_BRANCH] to run the script!"
  exit 1
fi

#######################################
# Populate the list with all branches #
#######################################
mapfile -t BRANCH_LIST < <(git for-each-ref --format='%(refname:short)' refs/heads/)

###############################
# Get total count of branches #
###############################
TOTAL_BRANCHES="${#BRANCH_LIST[@]}"

############################################################
# Go through all branches found locally and push to remote #
############################################################
for BRANCH in "${BRANCH_LIST[@]}";
do
  # Increment the counter
  ((COUNTER++))
  echo "-----------------------------------------"
  echo "Branch [${COUNTER}] of [${TOTAL_BRANCHES}]"
  echo "Checking out git Branch:[${BRANCH}]"
  git checkout "${BRANCH}"
  echo "Pushing git branch to remote..."
  if ! git push --force --set-upstream origin "${BRANCH}";
  then
    # Increment error count
    ((ERROR_COUNT++))
  fi
  echo "ERROR_CODE:[$?]"
  # Increment branch count
  ((BRANCH_COUNT++))
done

##########
# Footer #
##########
echo "-----------------------------------------"
echo "Pushed:[${BRANCH_COUNT}] of [${TOTAL_BRANCHES}] branches to remote"
echo "ERROR_COUNT:[${ERROR_COUNT}]"
echo "-----------------------------------------"
exit 0
```
