# GitHub Chaos Engine

A testing framework for creating complex GitHub environments to test edge cases, scaling, and performance.

## Overview

Chaos Engine creates various GitHub resources at scale to simulate real-world usage patterns and test edge cases. It can create organizations, repositories, pull requests, issues, users, and teams with complex relationships and activities.

## Key Features

- **Robust Retry Logic**: Handles API rate limits and race conditions during resource creation
- **Noninteractive Mode**: Support for automating the entire process without user prompts
- **Enhanced Validation**: Validation of configuration values to prevent common errors
- **Organization Verification**: Ensures organizations are fully provisioned before attempting dependent operations
- **Error Resilience**: Gracefully handles and recovers from API errors during operation

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
| `check-user-limits.sh` | Checks GitHub instance for user license limits | N/A |
| `clean-environment.sh` | Resets a GHES instance to near-fresh state | N/A |

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

# Optional settings
export AUTO_ADJUST_NUM_USERS=true  # Automatically adjust NUM_USERS based on license limits
export RUN_PR_APPROACHES=false     # Set to true to run all PR edge case approaches (creates extra PRs)
```

## Usage

Run all modules:
```bash
./build-enterprise.sh all
```

Run a specific module:
```bash
./build-enterprise.sh [orgs|repos|prs|issues|users|teams|check|clean|help]
```

### Noninteractive Mode

All modules now support noninteractive mode, which skips all prompts and uses default answers:
- `create-organizations.sh`
- `create-repositories.sh`
- `create-repo-prs.sh`
- `create-issues.sh`
- `create-teams.sh`
- `create-users.sh`
- `check-user-limits.sh`
- `clean-environment.sh`

This is automatically enabled when run through `build-enterprise.sh`, but can also be used directly:

```bash
./modules/create-organizations.sh --noninteractive
```

All scripts use a consistent `prompt_user()` function that detects noninteractive mode and automatically answers with default values, typically "yes".

## Requirements

- Bash shell environment
- `curl`, `jq`, `git`, and `openssl` commands
- GitHub Personal Access Token with appropriate scopes
- For organization creation: Enterprise Admin access
- For user creation: Enterprise Admin access (GitHub Enterprise Server only)

## Notes

- The `create-organizations.sh` and `create-users.sh` modules require Enterprise Admin/Site Admin privileges
- The GitHub token user must have site admin privileges for creating organizations
- Organization creation requires specifying a valid admin user (defaults to the authenticated user)
- User creation via API is only supported on GitHub Enterprise Server, not GitHub.com
- All operations use the same GitHub token specified in `config.env`

### Organization Creation Requirements

For successful organization creation:

1. **Site Admin Privileges**: The token user must have site admin privileges
2. **Valid Admin User**: The `ADMIN_USERNAME` in `config.env` must be:
   - A valid, existing user on the GitHub instance
   - If left blank, the authenticated user (from the token) will be used
3. **Valid Billing Email**: `BILLING_EMAIL` must be set to a valid email format

Common organization creation failures:
- **"Admin user could not be found"**: The specified admin user doesn't exist
- **"Not Found"**: The API endpoint doesn't exist or you lack site admin access
- **"Unauthorized"**: Your token doesn't have sufficient permissions

### Resource Creation Retry Logic

The scripts now include enhanced retry logic with exponential backoff:

1. **API Rate Limiting**: Scripts check for API rate limits before starting and warn if limits are too low
2. **Organization Verification**: Before creating dependent resources, scripts verify organizations exist with multiple retries
3. **Backoff Strategy**: Wait times increase with each retry to prevent overwhelming the server
4. **Race Condition Prevention**: Additional waiting periods ensure resources are fully provisioned before dependent operations

## Configuration Validation

The `test-config-values.sh` script validates all configuration settings before running:

```bash
./test-config-values.sh
```

The validation includes:
- Checking that all numeric values are valid numbers
- Ensuring values meet minimum requirements (e.g., NUM_ORGS ≥ 1)
- Validating boolean settings like RUN_PR_APPROACHES and AUTO_ADJUST_NUM_USERS
- Checking relationships between configuration values
- Validating that required settings like GITHUB_TOKEN are properly set

## Handling User Limits

GitHub Enterprise Server instances often have license limits on the number of users. The chaos-engine handles these limits in several ways:

1. Use the `check-user-limits` module to check available license seats before creating users:
   ```bash
   ./build-enterprise.sh check
   ```

2. Set `AUTO_ADJUST_NUM_USERS=true` in `config.env` to automatically adjust the number of users based on available license seats

## Error Handling

The enhanced scripts now include better error handling:

1. **API Rate Limit Handling**: Checks rate limits before starting operations
2. **Detailed Error Reporting**: Shows detailed HTTP responses for better troubleshooting
3. **Graceful Degradation**: Falls back to user namespace if organization creation fails
4. **Automatic Retries**: Retries failed operations with increasing wait times
5. **Error Explanation**: Provides contextual explanations for common error conditions

3. If user creation fails due to license limits, the script will:
   - Continue execution rather than failing completely

## Configuration Validation

You can validate your configuration by running:
```bash
./test-config-values.sh
```

This will:
1. Load and display all values from `config.env`
2. Validate that numeric values are actually numbers
3. Validate that boolean values are actually true/false

## Race Condition Handling

The scripts include robust retry logic to handle race conditions between different operations:

1. **Organization Creation**: Before repository and PR operations begin, the scripts will check if the target organization exists and wait for it with multiple retries.

2. **Repository Creation**: Repository operations include proper error handling and retries when the target organization is not yet fully created.

3. **Pull Request Creation**: PR operations implement similar retry logic to handle cases where repositories are not yet fully provisioned.

## PR Approach Options

Setting `RUN_PR_APPROACHES=true` in `config.env` will execute additional PR stress testing approaches:

1. **Empty commits + push**: Creates PRs with empty commits to test webhook triggers
2. **Force push patterns**: Tests force pushing to branches with open PRs
3. **Rapid concurrent operations**: Tests race conditions with concurrent API operations
4. **Rebase operations**: Tests squashing commits on branches with open PRs
5. **Direct refs manipulation**: Tests direct modification of refs via API

This is disabled by default to prevent creating excessive PR operations unless specifically testing these scenarios.
   
## Environment Cleanup

For GitHub Enterprise Server instances, you can reset the environment to a near-fresh state while preserving the license and admin user:

```bash
./build-enterprise.sh clean
```

This will:
1. Delete all organizations (which cascades to repositories, issues, PRs, etc.)
2. Delete all users except the authenticated admin user
3. Remove all enterprise announcements/broadcasts
4. Reset rate limits
5. Remove enterprise-level webhooks

**⚠️ WARNING: This is a destructive operation that cannot be undone!** The script will prompt for confirmation before proceeding.
   - Save any successfully created users for team creation
   - Provide informative error messages

4. If no users are available, team creation will still run but without members
