# GitHub Chaos Engine

A testing framework for creating complex GitHub environments to test edge cases, scaling, and performance.

## Overview

Chaos Engine creates various GitHub resources at scale to simulate real-world usage patterns and test edge cases. It can create organizations, repositories, pull requests, issues, users, and teams with complex relationships and activities.

## Modules

The following modules are available:

| Module | Description | Config Variable |
|--------|-------------|----------------|
| `create-organizations.sh` | Creates organizations with varied settings | `NUM_ORGS` |
| `create-repositories.sh` | Creates repositories with varied settings | `NUM_REPOS` |
| `create-repo-prs.sh` | Creates repositories with multiple PRs and edge-case operations | `NUM_PRS` |
| `create-issues.sh` | Creates issues with comments, labels, and reactions | `NUM_ISSUES` |
| `create-users.sh` | Creates test users and adds them to organizations | `NUM_USERS` |
| `create-teams.sh` | Creates teams with varied settings and memberships | `NUM_TEAMS` |

## Configuration

Configure the testing environment by editing `config.env`:

```bash
# Required settings
export GITHUB_TOKEN="your_token"    # PAT with appropriate scopes
export ORG="your-org"               # Target organization name
export WEBHOOK_URL="your_webhook"   # Webhook endpoint (e.g., smee.io URL)
export GITHUB_SERVER_URL="https://git.example.com"  # Comment for GitHub.com

# Testing parameters
export NUM_ORGS=3     # Number of organizations to create
export NUM_REPOS=5    # Number of repositories to create
export NUM_PRS=5      # Number of PRs to create
export NUM_ISSUES=10  # Number of issues to create
export NUM_USERS=10   # Number of users to create
export NUM_TEAMS=5    # Number of teams to create
```

## Usage

Run all modules:
```bash
./build-enterprise.sh
```

Run a specific module:
```bash
./build-enterprise.sh [orgs|repos|prs|issues|users|teams]
```

## Requirements

- Bash shell environment
- `curl`, `jq`, `git`, and `openssl` commands
- GitHub Personal Access Token with appropriate scopes
- For organization creation: Enterprise Admin access
- For user creation: Enterprise Admin access (GitHub Enterprise Server only)

## Notes

- The `create-organizations.sh` and `create-users.sh` modules require Enterprise Admin privileges
- User creation via API is only supported on GitHub Enterprise Server, not GitHub.com
- All operations use the same GitHub token specified in `config.env`
