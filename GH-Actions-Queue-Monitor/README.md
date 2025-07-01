# GitHub Actions Queue Monitor

A fast, lightweight bash script to monitor queued and running GitHub Actions jobs across your organization or specific repositories. Designed for auto-scaling decisions with self-hosted runners.

## Purpose

This tool helps organizations using self-hosted GitHub Actions runners to:
- Monitor queue backlogs across repositories
- Get near-time insights into workflow job status

## Features

- 🚀 **Fast scanning** - Optimized API calls and minimal validation
- 📊 **Dual monitoring** - Track both queued and running jobs
- 🎯 **Flexible targeting** - Monitor all repos or specific ones
- ⏱️ **Watch mode** - Continuous monitoring with configurable intervals
- 💾 **Configuration persistence** - Save/load settings for repeated use
- 🔍 **Error resilience** - Continue scanning even if some repos fail

## Requirements

- GitHub Personal Access Token with `repo` and `read:org` scopes

## Quick Start

```bash
# Basic usage - scan all repositories
./gha-jobs-queue-monitor.sh -o "myorg" -t "ghp_your_token_here"

# Monitor specific repositories only
./gha-jobs-queue-monitor.sh -o "myorg" -t "ghp_token" -r "webapp,api,worker"

# Include running jobs in analysis
./gha-jobs-queue-monitor.sh -o "myorg" -t "ghp_token" --include-running

# Continuous monitoring every 30 seconds
./gha-jobs-queue-monitor.sh -o "myorg" -t "ghp_token" --include-running -w -i 30
```

### Required Options

| Option | Description |
|--------|-------------|
| `-o, --org OWNER/ORG` | GitHub organization name (required) |
| `-t, --token TOKEN` | GitHub Personal Access Token (required) |

### Optional Flags

| Option | Description | Default |
|--------|-------------|---------|
| `-r, --repos REPO1,REPO2` | Comma-separated list of specific repositories | All repos |
| `--include-running` | Include running jobs in analysis | Disabled |
| `-w, --watch` | Continuous monitoring mode | Single check |
| `-i, --interval SECONDS` | Polling interval for watch mode | 60 seconds |
| `-s, --save-config` | Save configuration for future use | - |
| `-c, --load-config` | Load saved configuration | - |
| `--help` | Show help message | - |

## Examples

### Single Organization Scan
```bash
./gha-jobs-queue-monitor.sh -o "mycompany" -t "ghp_xxxxxxxxxxxxxxxxxxxx"
```

### Monitor Critical Repositories Only
```bash
./gha-jobs-queue-monitor.sh \
  -o "mycompany" \
  -t "ghp_xxxx" \
  -r "frontend,backend,api-gateway,payment-service"
```

### Full Monitoring with Running Jobs
```bash
./gha-jobs-queue-monitor.sh \
  -o "mycompany" \
  -t "ghp_xxxx" \
  --include-running \
  -w \
  -i 45
```

### Save Configuration for Repeated Use
```bash
# Save configuration
./gha-jobs-queue-monitor.sh \
  -o "mycompany" \
  -t "ghp_xxxx" \
  -r "critical-app,main-service" \
  --include-running \
  -s

# Later, use saved configuration
./gha-jobs-queue-monitor.sh -c -w
```

## Sample Output

### Basic Scan
```
GitHub Actions Queue Monitor (Optimized)
Organization: mycompany
Mode: Monitoring queued AND running jobs

Scanning all repositories in mycompany...
Checking mycompany/webapp... (2 queued, 3 running)
  └─ 2 queued
  └─ 3 running
Checking mycompany/api... (0 queued, 1 running)
  └─ 1 running
Checking mycompany/worker... (0 queued, 0 running)

=== SUMMARY ===
  Organization: mycompany
  Total repositories scanned: 3
  Total queued jobs: 2
  Total running jobs: 4
  Total active jobs: 6
```
## Configuration File

When using `-s, --save-config`, settings are saved to `.github-queue-config`:

```bash
GITHUB_ORG="mycompany"
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
SPECIFIC_REPOS="webapp,api,worker"
INCLUDE_RUNNING=true
POLL_INTERVAL=60
```

## Error Handling

The script is designed to be resilient:
- **API errors** are collected and displayed in the summary
- **Invalid repositories** don't stop the scan
- **Rate limiting** is handled gracefully

## Troubleshooting

### Common Issues

**"No repositories found"**
- Check organization name spelling
- Verify token has `read:org` permissions
- Ensure you have access to the organization

**"API rate limit exceeded"**
- GitHub allows 5,000 API requests per hour
- Use `-r` flag to limit repository scope
- Increase `-i` interval for watch mode

## License

MIT License - see LICENSE file for details.

---

**Author**: GitHub Copilot / @AppaTalks
**Created**: 2025-07-01  
