## Check Disk Space Script <br> for GitHub Enterprise Server (GHES) 

> [!NOTE]
> #### This script is independently maintained and is not [supported](https://docs.github.com/en/enterprise-server@3.13/admin/monitoring-managing-and-updating-your-instance/monitoring-your-instance/setting-up-external-monitoring) by GitHub.


## Features

### disk_check.sh
- Displays the server time at run time.
- Provides filesystem and inode information.
- Reports the largest directories (to 5 levels deep).
- Reports the largest files and the largest files older than 30 days.
- Excludes some directories from scans, ie. (`/proc` and `/data/user/docker/overlay2`).

### repo-analysis.sh
- Analyzes Git repositories in `/data/user/repositories` for large files.
- Reports repositories with files exceeding configurable size thresholds.

## Getting Started

### One-Liner to Run the Script

You can run the script directly from GitHub without cloning the repository. Use the following one-liner:

```sh
time bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/disk_check.sh)
```

## Credit

This script was adapted from Rackspace's documentation on troubleshooting low disk space for a Linux cloud server:
https://docs.rackspace.com/docs/troubleshooting-low-disk-space-for-a-linux-cloud-server

## License

This project is licensed under the [GPL-3.0 license]().

## Repository Analysis Tools

### repo-analysis.sh

Analyze Git repositories for large files:

```sh
# Run with default thresholds (1MB min, 25MB max)
sudo bash repo-analysis.sh

# Run with custom thresholds
SIZE_MIN_MB=10 SIZE_MAX_MB=50 sudo bash repo-analysis.sh

# Include deleted repositories
INCLUDE_DELETED=true sudo bash repo-analysis.sh
```

Run directly from GitHub (one-liner):

```sh
# Run with default thresholds
bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-analysis.sh)

# Run with custom thresholds
SIZE_MIN_MB=5 SIZE_MAX_MB=100 bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-analysis.sh)

# Run with debug mode enabled
DEBUG=true sudo bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-analysis.sh)
```

