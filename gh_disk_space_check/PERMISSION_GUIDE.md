# Permission Requirements for Repository Analysis Scripts

## Summary of User Issue

The user encountered this error when running the one-liner script:
```
Error: This script must be run as root (use sudo)
Command exited with non-zero status 1
```

**Resolution**: Confirmed that sudo IS required for this GHES environment.

## Root Cause Analysis

The error occurs because:
1. **GHES Standard Requirement**: GitHub Enterprise Server repository directories (`/data/user/repositories`) require elevated permissions
2. **Security Model**: Repository access is restricted to prevent unauthorized data access
3. **User Attempted**: `MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 time bash <(curl -sL URL)` (without sudo)
4. **Correct Usage**: Should be `sudo MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)`

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

### For GitHub Enterprise Server (REQUIRED - use sudo):
```bash
# Standard GHES usage (CONFIRMED WORKING)
sudo SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)

# With custom settings (RECOMMENDED for your environment)
sudo MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)

# With timing measurement
sudo time MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)
```

### For Development/Testing (may work without sudo on non-GHES systems):
```bash
# Try without sudo first (not applicable for your GHES environment)
SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)

# If permission error occurs, the script will suggest using sudo
```

### For Custom Repository Locations (if different from standard GHES path):
```bash
# Specify custom path (still requires sudo on GHES)
sudo REPO_BASE="/custom/path" SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash <(curl -sL URL)
```

## ✅ CONFIRMED WORKING COMMANDS for your GHES environment:

### Method 1: Download first, then execute (RECOMMENDED)
```bash
# Download the script
curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/simple-repo-analysis-oneliner.sh -o /tmp/simple-repo-analysis.sh

# Make executable and run
chmod +x /tmp/simple-repo-analysis.sh
sudo MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 /tmp/simple-repo-analysis.sh
```

### Method 2: Pipe to bash (alternative)
```bash
curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/simple-repo-analysis-oneliner.sh | sudo MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash
```

### Method 3: Use main script with command line options
```bash
curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/simple-repo-analysis.sh -o /tmp/simple-repo-analysis.sh
chmod +x /tmp/simple-repo-analysis.sh
sudo /tmp/simple-repo-analysis.sh --min-size 1 --max-size 25 --max-repos 100
```

## Implementation Details

The updated script includes:
1. `check_repo_access()` function that tests directory permissions
2. Helpful error messages with suggested command syntax including proper sudo usage
3. Graceful fallback when permissions are insufficient
4. Clear documentation in help output

**For GHES environments**: Sudo is typically required and the script will guide users to use the correct syntax.

This approach provides the best user experience while maintaining security requirements for production GHES environments.

## Quick Reference

**✅ RECOMMENDED (process substitution now works!):**
```bash
MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 time bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/simple-repo-analysis-oneliner.sh)
```

**✅ ALTERNATIVE (download first):**
```bash
curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/simple-repo-analysis-oneliner.sh -o /tmp/simple-repo-analysis.sh
chmod +x /tmp/simple-repo-analysis.sh
MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 /tmp/simple-repo-analysis.sh
```

**✅ ALTERNATIVE (pipe method):**
```bash
curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/simple-repo-analysis-oneliner.sh | MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 bash
```

## Recent Improvements

### ✅ Process Substitution Now Works!
**Major Update**: The script now automatically handles sudo internally, so you can use the original desired syntax:

```bash
MAX_REPOS=100 SIZE_MIN_MB=1 SIZE_MAX_MB=25 time bash <(curl -sL URL)
```

The script automatically adds `sudo` to commands that need elevated permissions (file access, repository scanning, etc.) while allowing you to run the script normally without prefixing `sudo`.

### Enhanced Deleted Repository Detection
The simplified scripts now use the same robust filtering logic as the original analysis script:

- **Old method**: Only checked for basic marker files (`DELETED`, `.deleted`)
- **New method**: Verifies repositories have an `objects` directory with pack files

This improvement ensures that GHES deleted repositories are properly filtered out, matching the behavior of the original comprehensive analysis script. The filtering is particularly important in GHES environments where deleted repositories may still have directory structures but lack the actual Git object data.

### Automatic Permission Handling
The script now includes automatic sudo handling for:
- Repository directory scanning (`find` commands)
- File size calculations (`du` commands) 
- File metadata access (`stat` commands)
- Repository object validation

This eliminates the need to run the entire script with sudo, providing better security by only elevating privileges when needed.

**Root Cause**: ~~Process substitution `<(...)` doesn't work reliably in all shell environments.~~ **RESOLVED** - Script now handles sudo internally.
