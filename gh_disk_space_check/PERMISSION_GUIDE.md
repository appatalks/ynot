# Permission Requirements for Repository Analysis Scripts

## Summary of User Issue

The user encountered this error when running the one-liner script:
```
Error: This script must be run as root (use sudo)
Command exited with non-zero status 1
```

## Root Cause Analysis

The error occurs because:
1. The GitHub version of the script may have a strict root check
2. GHES repository directories (`/data/user/repositories`) typically require elevated permissions
3. The user tried to run without sudo: `MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 time bash <(curl -sL URL)`

## Solutions Implemented

### 1. Smart Permission Detection
Updated the one-liner script to:
- Check if repository directory is accessible before requiring sudo
- Provide helpful error messages when permissions are needed
- Allow the script to run without sudo when possible

### 2. Flexible Permission Handling
The script now:
- Tests directory access first
- Only suggests sudo when actually needed
- Provides clear instructions for both scenarios

### 3. Updated Documentation
- Added examples showing both sudo and non-sudo usage
- Clarified when sudo is required vs optional
- Provided environment variable examples for different permission levels

## Recommended Usage Patterns

### For GitHub Enterprise Server (typical case - requires sudo):
```bash
# Standard GHES usage
sudo SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)

# With custom settings
sudo MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)
```

### For Development/Testing (may not require sudo):
```bash
# Try without sudo first
SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)

# If permission error occurs, the script will suggest using sudo
```

### For Custom Repository Locations:
```bash
# Specify custom path
REPO_BASE="/custom/path" SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)
```

## Implementation Details

The updated script includes:
1. `check_repo_access()` function that tests directory permissions
2. Helpful error messages with suggested command syntax
3. Graceful fallback when permissions are insufficient
4. Clear documentation in help output

This approach provides the best user experience while maintaining security requirements for production GHES environments.
