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
# e.g. ./build-enterprise.sh all|repos|teams
MODE="${1:-all}"

run_module() {
  local mod="$1"
  echo -e "\n➡️  Running module: $mod\n"
  bash "$SCRIPT_DIR/modules/$mod.sh"
}

# Add new module $<FUNCTIONs>.sh to this case.
case "$MODE" in
  all)
    run_module create-repo-prs
    # next you could add:
    # run_module add-users-to-teams
    ;;
  repos)     run_module create-repo-prs ;;
  teams)     run_module add-users-to-teams ;;
  *)
    echo "Usage: $0 [all|repos|teams]" >&2
    exit 1
    ;;
esac

echo -e "\n🎉  build-enterprise.sh complete!"
