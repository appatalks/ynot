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
git config --global credential.helper ""
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
  bash "$SCRIPT_DIR/modules/$mod.sh"
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
  
  # Set defaults for missing NUM_* variables
  : "${NUM_ORGS:=1}"
  : "${NUM_REPOS:=1}"
  : "${NUM_PRS:=1}"
  : "${NUM_ISSUES:=1}"
  : "${NUM_USERS:=1}"
  : "${NUM_TEAMS:=1}"
  
  # Export these values so they persist for any subsequent commands
  export NUM_ORGS NUM_REPOS NUM_PRS NUM_ISSUES NUM_USERS NUM_TEAMS
  
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
  if bash "$SCRIPT_DIR/modules/$mod.sh"; then
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
    # If generated-users.txt doesn't exist or is empty, ask about team creation
    if [[ ! -f "$SCRIPT_DIR/generated-users.txt" || ! -s "$SCRIPT_DIR/generated-users.txt" ]]; then
      echo -e "\n⚠️  No users available for teams. Teams will be created without members."
      echo -n "Do you want to continue with team creation? (y/n) "
      read -r CONTINUE_TEAMS
      if [[ "$CONTINUE_TEAMS" =~ ^[Yy]$ ]]; then
        run_module_safe create-teams true
      else
        echo -e "\n⚠️  Skipping team creation as requested"
      fi
    else
      # We have users, proceed with team creation
      run_module_safe create-teams true
    fi
    if [[ -f "$SCRIPT_DIR/generated-users.txt" ]] && [[ -s "$SCRIPT_DIR/generated-users.txt" ]]; then
      run_module_safe create-teams true
    else
      echo -e "\n⚠️  Skipping teams creation - no users available"
    fi
    ;;
  orgs)      run_module create-organizations ;;
  repos)     run_module create-repositories ;;
  prs)       run_module create-repo-prs ;;
  issues)    run_module create-issues ;;
  users)     run_module create-users ;;
  teams)     run_module create-teams ;;
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
