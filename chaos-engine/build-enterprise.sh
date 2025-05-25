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

# (Optional) parse arguments to run only a subset of modules
# e.g. ./build-enterprise.sh all|orgs|repos|issues|users|teams|prs
MODE="${1:-all}"

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
    missing=true
  fi
  
  if [[ -z "${WEBHOOK_URL}" ]]; then
    echo "⚠ Missing WEBHOOK_URL in config.env" >&2
    missing=true
  fi
  
  # For the "all" mode, validate all required variables are set
  if [[ "$MODE" == "all" ]]; then
    if [[ -z "$NUM_ORGS" ]]; then echo "⚠ Missing NUM_ORGS in config.env" >&2; missing=true; fi
    if [[ -z "$NUM_REPOS" ]]; then echo "⚠ Missing NUM_REPOS in config.env" >&2; missing=true; fi
    if [[ -z "$NUM_PRS" ]]; then echo "⚠ Missing NUM_PRS in config.env" >&2; missing=true; fi
    if [[ -z "$NUM_ISSUES" ]]; then echo "⚠ Missing NUM_ISSUES in config.env" >&2; missing=true; fi
    if [[ -z "$NUM_USERS" ]]; then echo "⚠ Missing NUM_USERS in config.env" >&2; missing=true; fi
    if [[ -z "$NUM_TEAMS" ]]; then echo "⚠ Missing NUM_TEAMS in config.env" >&2; missing=true; fi
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

# Add new module $<FUNCTIONs>.sh to this case.
case "$MODE" in
  all)
    run_module create-organizations
    run_module create-repositories
    run_module create-repo-prs
    run_module create-issues
    run_module create-users
    run_module create-teams
    ;;
  orgs)      run_module create-organizations ;;
  repos)     run_module create-repositories ;;
  prs)       run_module create-repo-prs ;;
  issues)    run_module create-issues ;;
  users)     run_module create-users ;;
  teams)     run_module create-teams ;;
  *)
    echo "Usage: $0 [all|orgs|repos|prs|issues|users|teams]" >&2
    exit 1
    ;;
esac

echo -e "\n🎉  build-enterprise.sh complete!"
