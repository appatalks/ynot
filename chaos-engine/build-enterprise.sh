#!/usr/bin/env bash
# build-enterprise.sh
# ─────────────────────────────────────────────────────────────────────────────
# Master entrypoint: loads config, then runs each “module” in turn.
set -euo pipefail

# resolve our directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# load all settings
source "$SCRIPT_DIR/config.env"

# disable credential helpers / SSL prompts globally
# git config --global credential.helper ""
git config credential.helper "" # Leave as local to this script
export GIT_SSL_NO_VERIFY GIT_TERMINAL_PROMPT

# Display help function
show_help() {
  cat << EOF
Chaos Engine - GitHub Test Environment Builder

Usage: 
  $(basename "$0") [option]

Options:
  all       Run all modules in sequence
  orgs      Create organizations only
  repos     Create repositories only
  prs       Create pull requests only
  issues    Create issues only
  users     Create users only
  teams     Create teams only
  blobs     Add various sized files and media to repositories
  check     Check user license limits only
  clean     Clean up GHES environment (keeps only license and admin user)
  help      Display this help message

For detailed configuration, edit config.env before running.
EOF
}

# Parse arguments to run only a subset of modules
if [[ $# -eq 0 ]]; then
  show_help
  exit 0
fi

MODE="$1"

run_module() {
  local mod="$1"
  echo -e "\n➡️  Running module: $mod\n"
  
  # All modules now support the --noninteractive flag to suppress prompts
  bash "$SCRIPT_DIR/modules/$mod.sh" --noninteractive
  
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo -e "\n⚠️  Module $mod failed with exit code $status"
  fi
  
  # Return the module's exit code
  return $status
}

# Validate environment variables
validate_env_vars() {
  local missing=false
  
  if [[ -z "${GITHUB_TOKEN}" ]]; then
    echo "⚠ Missing GITHUB_TOKEN in config.env" >&2
    missing=true
  fi
  
  if [[ -z "${ORG}" ]]; then
    echo "⚠ Missing ORG in config.env" >&2
    echo "Organization will be created if it doesn't exist" >&2
  fi
  
  if [[ -z "${WEBHOOK_URL}" ]]; then
    echo "⚠ Missing WEBHOOK_URL in config.env" >&2
    missing=true
  fi
  
  # Validate numeric values
  validate_numeric() {
    local val="$1"
    local name="$2"
    local min="${3:-0}"  # Default minimum is 0
    
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
      echo "⚠ Invalid $name value: ${val}. Must be a number." >&2
      missing=true
      return 1
    elif [[ "$val" -lt "$min" ]]; then
      echo "⚠ Invalid $name value: ${val}. Must be at least $min." >&2
      missing=true
      return 1
    fi
    return 0
  }
  
  # Validate boolean values
  validate_boolean() {
    local val="$1"
    local name="$2"
    
    if [[ "$val" != "true" && "$val" != "false" ]]; then
      echo "⚠ Invalid $name value: ${val}. Must be 'true' or 'false'." >&2
      missing=true
      return 1
    fi
    return 0
  }

  # Validate numeric configurations with minimum values
  validate_numeric "$NUM_ORGS" "NUM_ORGS" 1 || true
  validate_numeric "$NUM_REPOS" "NUM_REPOS" 0 || true
  validate_numeric "$NUM_PRS" "NUM_PRS" 0 || true
  validate_numeric "$NUM_ISSUES" "NUM_ISSUES" 0 || true
  validate_numeric "$NUM_USERS" "NUM_USERS" 0 || true
  validate_numeric "$NUM_TEAMS" "NUM_TEAMS" 0 || true
  
  # Validate boolean configurations
  validate_boolean "${RUN_PR_APPROACHES:-false}" "RUN_PR_APPROACHES" || true
  validate_boolean "${AUTO_ADJUST_NUM_USERS:-true}" "AUTO_ADJUST_NUM_USERS" || true
  validate_boolean "${DATA_BLOBS:-false}" "DATA_BLOBS" || true
  
  # Validate blob size configurations if DATA_BLOBS is true
  if [[ "${DATA_BLOBS:-false}" == "true" ]]; then
    validate_numeric "${BLOB_MIN_SIZE:-1}" "BLOB_MIN_SIZE" 1 || true
    validate_numeric "${BLOB_MAX_SIZE:-10}" "BLOB_MAX_SIZE" 1 || true
    validate_numeric "${BLOB_REPOS_COUNT:-3}" "BLOB_REPOS_COUNT" 1 || true
    
    # Check if min size is less than or equal to max size
    if [[ "${BLOB_MIN_SIZE:-1}" -gt "${BLOB_MAX_SIZE:-10}" ]]; then
      echo "⚠ BLOB_MIN_SIZE (${BLOB_MIN_SIZE:-1}) cannot be larger than BLOB_MAX_SIZE (${BLOB_MAX_SIZE:-10})" >&2
      missing=true
    fi
  fi

  # Get the values from config.env - don't use defaults
  # This ensures we use the actual values from the config file
  echo "Configuration values from config.env:"
  echo "- ORG: ${ORG}"
  echo "- NUM_ORGS: ${NUM_ORGS}"
  echo "- NUM_REPOS: ${NUM_REPOS}" 
  echo "- NUM_PRS: ${NUM_PRS}"
  echo "- NUM_ISSUES: ${NUM_ISSUES}"
  echo "- NUM_USERS: ${NUM_USERS}"
  echo "- NUM_TEAMS: ${NUM_TEAMS}"
  echo "- RUN_PR_APPROACHES: ${RUN_PR_APPROACHES:-false}"
  echo "- DATA_BLOBS: ${DATA_BLOBS:-false}"
  if [[ "${DATA_BLOBS:-false}" == "true" ]]; then
    echo "- BLOB_MIN_SIZE: ${BLOB_MIN_SIZE:-1} MB"
    echo "- BLOB_MAX_SIZE: ${BLOB_MAX_SIZE:-10} MB"
    echo "- BLOB_REPOS_COUNT: ${BLOB_REPOS_COUNT:-3}"
  fi
  
  # Validate numeric values
  if ! [[ "$NUM_ORGS" =~ ^[0-9]+$ ]]; then
    echo "⚠ Invalid NUM_ORGS value: ${NUM_ORGS}. Must be a number." >&2
    missing=true
  fi
  
  if ! [[ "$NUM_REPOS" =~ ^[0-9]+$ ]]; then
    echo "⚠ Invalid NUM_REPOS value: ${NUM_REPOS}. Must be a number." >&2
    missing=true
  fi
  
  if ! [[ "$NUM_PRS" =~ ^[0-9]+$ ]]; then
    echo "⚠ Invalid NUM_PRS value: ${NUM_PRS}. Must be a number." >&2
    missing=true
  fi
  
  # Only set defaults if values are completely missing (shouldn't happen with source)
  : "${NUM_ORGS:=1}"
  : "${NUM_REPOS:=1}"
  : "${NUM_PRS:=1}"
  : "${NUM_ISSUES:=1}"
  : "${NUM_USERS:=1}" 
  : "${NUM_TEAMS:=1}"
  : "${RUN_PR_APPROACHES:=false}"
  : "${DATA_BLOBS:=false}"
  : "${BLOB_MIN_SIZE:=1}"
  : "${BLOB_MAX_SIZE:=10}"
  : "${BLOB_REPOS_COUNT:=3}"
  
  # Export these values so they persist for any subsequent commands
  export NUM_ORGS NUM_REPOS NUM_PRS NUM_ISSUES NUM_USERS NUM_TEAMS RUN_PR_APPROACHES
  export DATA_BLOBS BLOB_MIN_SIZE BLOB_MAX_SIZE BLOB_REPOS_COUNT
  
  # For validation purposes only, check module-specific variables
  if [[ "$MODE" == "all" ]]; then
    # All variables are set with defaults above
    :
  else
    # For specific modes, validate only the relevant variables
    case "$MODE" in
      orgs)  if [[ -z "$NUM_ORGS" ]]; then echo "⚠ Missing NUM_ORGS in config.env" >&2; missing=true; fi ;;
      repos) if [[ -z "$NUM_REPOS" ]]; then echo "⚠ Missing NUM_REPOS in config.env" >&2; missing=true; fi ;;
      prs)   if [[ -z "$NUM_PRS" ]]; then echo "⚠ Missing NUM_PRS in config.env" >&2; missing=true; fi ;;
      issues) if [[ -z "$NUM_ISSUES" ]]; then echo "⚠ Missing NUM_ISSUES in config.env" >&2; missing=true; fi ;;
      users) if [[ -z "$NUM_USERS" ]]; then echo "⚠ Missing NUM_USERS in config.env" >&2; missing=true; fi ;;
      teams) if [[ -z "$NUM_TEAMS" ]]; then echo "⚠ Missing NUM_TEAMS in config.env" >&2; missing=true; fi ;;
      blobs) if [[ "$DATA_BLOBS" != "true" ]]; then echo "⚠ DATA_BLOBS must be set to 'true' to use this module" >&2; missing=true; fi ;;
    esac
  fi
  
  if $missing; then
    echo -e "\n❌ Configuration errors detected. Please check config.env and try again.\n"
    exit 1
  fi
}

# Validate environment variables before executing any modules
validate_env_vars

# Function to run a module and check if it succeeded
run_module_safe() {
  local mod="$1"
  local continue_on_error="${2:-false}"
  
  echo -e "\n➡️  Running module: $mod\n"
  if bash "$SCRIPT_DIR/modules/$mod.sh" --noninteractive; then
    echo -e "\n✅  Module $mod completed successfully"
    return 0
  else
    local status=$?
    echo -e "\n⚠️  Module $mod failed with exit code $status"
    if [[ "$continue_on_error" == "true" ]]; then
      echo "Continuing execution despite error..."
      return 0
    else
      return $status
    fi
  fi
}

# Add new module $<FUNCTIONs>.sh to this case.
case "$MODE" in
  all)
    # Check user limits before beginning (helpful but optional)
    if [[ "$GITHUB_SERVER_URL" != "https://github.com" ]]; then
      run_module_safe check-user-limits true
    fi
    
    # These modules have to succeed for the rest to work
    run_module_safe create-organizations || exit 1
    run_module_safe create-repositories || exit 1
    
    # These modules can fail but we'll still continue
    run_module_safe create-repo-prs true
    run_module_safe create-issues true
    
    # Only create users if NUM_USERS > 0
    if [[ "$NUM_USERS" -gt 0 ]]; then
      run_module_safe create-users true  # Users might fail if license limits reached
    else
      echo -e "\n⚠️  Skipping user creation - NUM_USERS is set to 0"
    fi
    
    # Check if we have users before creating teams
    # If generated-users.txt doesn't exist or is empty, teams will be without members
    if [[ ! -f "$SCRIPT_DIR/generated-users.txt" || ! -s "$SCRIPT_DIR/generated-users.txt" ]]; then
      echo -e "\n⚠️  No users available for teams. Teams will be created without members."
      # In noninteractive mode, proceed with team creation
      run_module_safe create-teams true
    else
      # We have users, proceed with team creation
      run_module_safe create-teams true
    fi
    if [[ -f "$SCRIPT_DIR/generated-users.txt" ]] && [[ -s "$SCRIPT_DIR/generated-users.txt" ]]; then
      run_module_safe create-teams true
    else
      echo -e "\n⚠️  Skipping teams creation - no users available"
    fi
    
    # Add blob data if DATA_BLOBS is true
    if [[ "${DATA_BLOBS:-false}" == "true" ]]; then
      run_module_safe create-blob-data true
    else
      echo -e "\n⚠️  Skipping blob data creation - DATA_BLOBS is not set to 'true'"
    fi
    ;;
  orgs)      run_module create-organizations ;;
  repos)     run_module create-repositories ;;
  prs)       run_module create-repo-prs ;;
  issues)    run_module create-issues ;;
  users)     run_module create-users ;;
  teams)     run_module create-teams ;;
  blobs)     run_module create-blob-data ;;
  check)     run_module check-user-limits ;;
  clean)     
    if [[ "$GITHUB_SERVER_URL" == "https://github.com" ]]; then
      echo "⚠️ The clean option is only available for GitHub Enterprise Server instances."
      echo "It should not be run against GitHub.com."
      exit 1
    fi
    run_module clean-environment ;;
  help)      show_help; exit 0 ;;
  *)
    echo -e "⚠️  Unknown option: $MODE\n" >&2
    show_help
    exit 1
    ;;
esac

echo -e "\n🎉  build-enterprise.sh complete!"
