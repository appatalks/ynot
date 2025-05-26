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

### repo-filesize-analysis.sh
- Analyzes Git repositories in `/data/user/repositories` for large files.
- Reports repositories with files exceeding configurable size thresholds.
- Generates detailed reports of large files in plain text format.
- Can automatically resolve Git object hashes to actual filenames.
- Integrates with GitHub Enterprise Server's `ghe-nwo` command to display proper repository names.

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

### repo-filesize-analysis.sh

Analyze Git repositories for large files:

```sh
# Run with default thresholds (100MB min, 400MB max)
sudo bash repo-filesize-analysis.sh

# Run with custom thresholds
SIZE_MIN_MB=25 SIZE_MAX_MB=100 sudo bash repo-filesize-analysis.sh

# Run with automatic object resolution
SIZE_MIN_MB=25 SIZE_MAX_MB=100 RESOLVE_OBJECTS=true sudo bash repo-filesize-analysis.sh
```

Run directly from GitHub (one-liner):

```sh
# Run with default thresholds
sudo bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-filesize-analysis.sh)

# Run with custom thresholds and object resolution
SIZE_MIN_MB=1 SIZE_MAX_MB=25 RESOLVE_OBJECTS=true sudo bash <(curl -sL https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/repo-filesize-analysis.sh)
```

### resolve-pack-objects.sh

This tool helps you resolve Git pack objects to real filenames:

```sh
./resolve-pack-objects.sh -p /path/to/pack/file.pack -r /path/to/repository.git
```

### process-packs-report.sh

Process the output of repo-filesize-analysis.sh to get detailed information about each pack file:

```sh
./process-packs-report.sh -f /tmp/repos_100mb_to_400mb.txt
```

When you enable object resolution with `RESOLVE_OBJECTS=true`, the script will:

1. First try to find the helper scripts in the same directory
2. If not found, automatically download them from GitHub
3. Generate detailed reports showing which actual files exist within the Git pack files

This helps you identify specific large files within each repository, rather than just seeing the pack file names.

