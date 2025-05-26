# Chaos Engine Modules

This directory contains the individual modules that make up the Chaos Engine testing suite. Each script is designed to test different aspects of a GitHub Enterprise instance.

## Available Modules

- `check-user-limits.sh` - Checks user license limits on a GitHub Enterprise instance
- `clean-environment.sh` - Cleans up a GitHub Enterprise instance (resets to initial state)
- `create-blob-data.sh` - Adds various sized files and media to repositories
- `create-issues.sh` - Creates issues with comments and attachments
- `create-organizations.sh` - Creates organizations in a GitHub Enterprise instance
- `create-repo-prs.sh` - Creates repositories and pull requests
- `create-repositories.sh` - Creates repositories with different settings
- `create-teams.sh` - Creates teams and assigns members
- `create-users.sh` - Creates test users on a GitHub Enterprise instance

## Module Details

### create-blob-data.sh

This module adds various sized files and media to existing repositories. It can be used to test repository storage, bandwidth, and API functionality with larger files.

#### Configuration

The module uses the following environment variables from `config.env`:

```bash
# Blob data options
export DATA_BLOBS=false            # Set to true to add blob data to repositories
export BLOB_MIN_SIZE=1             # Minimum size in MB for blob data per repository
export BLOB_MAX_SIZE=10            # Maximum size in MB for blob data per repository
export BLOB_REPOS_COUNT=3          # Number of repositories to add blob data to
```

#### Usage

To run this module independently:

```bash
./build-enterprise.sh blobs
```

To include it in the full testing suite, set `DATA_BLOBS=true` in your `config.env`.

#### Data Sources

The module downloads sample media files from:
- PNG files: `https://github.com/appatalks/closetemail.com/tree/generated/generated/images`
- TAR.GZ files: `https://github.com/appatalks/closetemail.com/tree/generated/generated/images/a`

Additionally, it generates random binary files to meet the specified size requirements.

#### Behavior

For each selected repository:
1. Creates a new branch
2. Downloads sample media files 
3. Generates additional random files to reach the target size (between BLOB_MIN_SIZE and BLOB_MAX_SIZE)
4. Commits all files to the repository
5. Creates a pull request with the changes

This helps simulate real-world repository growth and tests how GitHub handles repositories with larger files and various file types.
