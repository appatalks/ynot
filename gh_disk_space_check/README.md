## Check Disk Space Script <br> for GitHub Enterprise Server (GHES) 

> [!NOTE]
> #### This script is independently maintained and is not [supported](https://docs.github.com/en/enterprise-server@3.13/admin/monitoring-managing-and-updating-your-instance/monitoring-your-instance/setting-up-external-monitoring) by GitHub.

Use (`disk_check.sh`) to quickly monitor disk space usage on a GitHub Enterprise Server ([GHES](https://docs.github.com/en/enterprise-server@3.13/admin/all-releases)).

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
- Generates detailed reports of large files in plain text format.
- Integrates with GitHub Enterprise Server's `ghe-nwo` command to display proper repository names.
- Supports compressed repository paths with `/nw/` format (May 2025 update).
- Shows friendly repository names in both summary report and output files.
- Efficient single-script solution for repository file analysis
- Clean, maintainable code with comprehensive reporting
- No external dependencies or additional script requirements
- Configurable via command line options or environment variables
- Easy to understand and modify for specific needs

## Getting Started

### One-Liner to Run the Script

You can run the script directly from GitHub without cloning the repository. Use the following one-liner:

```sh
time bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/disk_check.sh)
```

### Optional add to ```cron```

To run the script every ```15 minutes``` as the "**admin**" user, follow these steps:

1. Download the script to `/home/admin`:

    ```sh
    curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/disk_check.sh -o /home/admin/disk_check.sh
    chmod +x /home/admin/disk_check.sh
    ```

2. Open the crontab for the ```admin``` user:

    ```sh
    crontab -e
    ```

3. Add the following line to the crontab:

    ```sh
    */15 * * * * bash /home/admin/disk_check.sh >> /home/admin/disk_check.log 2>&1
    ```

    This will run the script every 15 minutes and append the output to `/home/admin/disk_check.log`. <br>
    Remeber to remove from cron and purge the log when no longer required. Or risk running out of disk space!!

## Author

- appatalks

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
sudo bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-analysis.sh)

# Run with custom thresholds
SIZE_MIN_MB=5 SIZE_MAX_MB=100 sudo bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-analysis.sh)

# Run with debug mode enabled
DEBUG=true sudo bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-analysis.sh)
```

### Command-Line Options

The repo-analysis.sh script supports the following command-line options:

```sh
--min-size VALUE    Set minimum file size in MB (default: 1)
--max-size VALUE    Set maximum file size in MB (default: 25)
--max-repos VALUE   Set maximum repositories to analyze (default: 10)
--max-objects VALUE Set maximum objects per repository (default: 10)
--include-deleted   Include deleted repositories in analysis
--base-path PATH    Set custom repository base path
--debug             Enable debug output
--help              Show help information
```

Example:
```sh
sudo bash repo-analysis.sh --min-size 2 --max-size 10 --max-repos 20 --include-deleted
```

### Important Notes on Permissions and Repository Paths

1. **Run with sudo**: This script needs to access Git repositories that may have restricted permissions, so it should be run with `sudo`.
   
2. **Repository Path Formats**: The script handles multiple repository path formats:
   - Standard organization/repository format (resolved via ghe-nwo)
   - Direct filesystem paths like `/data/user/repositories/org/repo.git`
   - Compressed nested path format like `c/nw/c7/4d/97/16/16` used by GitHub Enterprise Server
   
3. **Repository Resolution**: If repositories can't be found, the script will:
   - Try multiple potential locations (with/without .git suffix)
   - Attempt pattern matching to find repository paths
   - Fall back to using the internal path when resolution fails

4. **Path Handling**: The script automatically handles:
   - Path format detection for both standard and compressed paths
   - Path normalization to correct representations
   - Friendly name resolution via ghe-nwo
   - Mapping between internal paths and friendly names

## Performance Optimizations

The repo-analysis.sh script includes optimizations for installations with large numbers of repositories:

### Environment Variables and Performance

You can control the behavior of repo-analysis.sh with these environment variables:

```sh
# Basic configuration
SIZE_MIN_MB=1          # Minimum file size in MB
SIZE_MAX_MB=25         # Maximum file size in MB  
MAX_REPOS=10           # Max repositories to analyze in detail
MAX_OBJECTS=10         # Max objects per repository
INCLUDE_DELETED=false  # Include deleted repositories
REPO_BASE="/data/user/repositories"  # Repository base path
DEBUG=false            # Enable detailed debug output
```

### Repository Analysis Approach

The script works efficiently on large installations by:

- Analyzing only the most relevant repositories 
- Processing repositories in order of size (largest first)
- Limiting the depth of analysis to preserve performance
- Optimizing file discovery with size-based find commands
- Using a two-phase approach: quick scanning followed by detailed analysis

### Sample Output

Here's an example of the output you can expect from repo-analysis.sh:

```
ANALYSIS SETTINGS:
- Minimum file size: 2MB
- Maximum file size: 10MB
- Max repositories to analyze in detail: 10
- Max objects per repository: 10
- Include deleted repositories: false

Analyzing repositories in /data/user/repositories...
Initial estimate: 317M	/data/user/repositories/
Scanning for repositories...
Found 122 active repositories after filtering
Performing file scan on all active repositories...
PHASE 1: Quick scan of all repositories for large files...
Total repository storage: 0.30 GB across 122 repositories
PHASE 2: Detailed analysis of largest repositories...
Performing detailed analysis on top 10 largest repositories...
Skipping detailed analysis - already collected data in Phase 1
Deduplicating result files...
Identifying repositories for name resolution...
Building repository path mappings...
Resolving friendly names for top 10 repositories with large files...
Successfully resolved 2 repository names
Repository name cache entries:
  org-a/repo-name -> org-a/hook-edge-1748226694
  actions/labeler -> actions/labeler

======================================
REPOSITORY FILE SIZE ANALYSIS SUMMARY
======================================
Total repositories found: 122

FINDINGS SUMMARY:
----------------
1. Repositories with files > 10MB: 5
   Total files > 10MB: 5

2. Repositories with files 2MB-10MB: 19
   Total files 2MB-10MB: 20

TOP 5 REPOSITORIES WITH LARGEST FILES:
------------------------------------
  org-b/data-service: 1 large files
  org-c/api-gateway: 1 large files
  org-d/image-processor: 1 large files
  org-e/backend-service: 1 large files
  org-f/frontend-app: 1 large files

REPORTS LOCATION:
---------------
* Files over 10MB: /tmp/repos_over_10mb.txt
* Files between 2MB-10MB: /tmp/repos_2mb_to_10mb.txt

Analysis completed: Tue 27 May 2025 05:52:38 AM UTC
```

## Output Files

When run, repo-analysis.sh generates two output files:

1. `/tmp/repos_over_[MAX_SIZE]mb.txt` - Contains files larger than the maximum size threshold
2. `/tmp/repos_[MIN_SIZE]mb_to_[MAX_SIZE]mb.txt` - Contains files between minimum and maximum size thresholds

Example output file contents:
```
org-b/data-service:objects/pack/pack-cb57fdc311f75da868ea1ecef6fdc1691c6be19e.pack (24.45MB)
org-c/api-gateway:objects/pack/pack-653bd255bf8474f21f9087b3b4294ca5ba6fe255.pack (26.76MB)
org-d/image-processor:objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack (80.22MB)
org-e/backend-service:objects/pack/pack-4690736ef7ecdf1e00b11cce5a6a7c4b9b6ba80e.pack (22.70MB)
org-f/frontend-app:objects/pack/pack-75a64528b945d0e5855e2c52ae006f8232a81589.pack (16.79MB)
```

The files include:
- Repository name (friendly format if resolution was successful)
- Path to the large file within the repository
- Size of the file in human-readable format

## Conclusion

The repo-analysis.sh script provides a quick and efficient way to analyze Git repositories on GitHub Enterprise Server for large files. Key advantages:

1. **Easy to use**: Simple command-line interface with sensible defaults
2. **Detailed reports**: Generates comprehensive reports with file sizes and paths
3. **Human-readable output**: Shows friendly repository names instead of internal paths
4. **Optimized performance**: Fast analysis even on large installations
5. **Flexible configuration**: Adjustable thresholds to focus on files of specific sizes
6. **Path format handling**: Supports both standard and compressed repository paths

For more information, please refer to the script's help information by running:
```sh
sudo bash repo-analysis.sh --help
```

