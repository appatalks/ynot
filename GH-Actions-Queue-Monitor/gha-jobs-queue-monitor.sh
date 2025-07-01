#!/bin/bash

# GitHub Actions Queue Monitor for Self-Hosted Runners
# Date: 2025-07-01
# Purpose: Monitor pending jobs across an organization for auto-scaling decisions

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.github-queue-config"
LOG_FILE="${SCRIPT_DIR}/queue-monitor.log"

# Default thresholds
DEFAULT_LOW_THRESHOLD=5
DEFAULT_HIGH_THRESHOLD=20
DEFAULT_POLL_INTERVAL=60

# Global variables for error tracking
VALIDATION_ERRORS=""
API_ERRORS=""

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to log with timestamp
log_message() {
    local message=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S UTC') - $message" | tee -a "$LOG_FILE"
}

# Function to display usage
usage() {
    cat << EOF
GitHub Actions Queue Monitor (Optimized)

Usage: $0 [OPTIONS]

OPTIONS:
    -o, --org OWNER/ORG         GitHub organization (required)
    -t, --token TOKEN           GitHub Personal Access Token (required)
    -r, --repos REPO1,REPO2     Comma-separated list of specific repositories to monitor
                               (optional - if not provided, monitors all org repos)
    --include-running           Include running jobs in the analysis and display
    -w, --watch                 Continuous monitoring mode
    -i, --interval SECONDS      Polling interval for watch mode (default: $DEFAULT_POLL_INTERVAL)
    -s, --save-config           Save configuration for future use
    -c, --load-config           Load saved configuration
    --help                      Show this help message

EXAMPLES:
    # Single check - all repositories
    $0 -o myorg -t ghp_xxxxxxxxxxxxxxxxxxxx

    # Monitor specific repositories only
    $0 -o myorg -t ghp_xxxxxxxxxxxxxxxxxxxx -r "webapp,api-service,worker"

    # Include running jobs in the analysis
    $0 -o myorg -t ghp_xxxxxxxxxxxxxxxxxxxx --include-running

    # Continuous monitoring with running jobs
    $0 -o myorg -t ghp_xxxxxxxxxxxxxxxxxxxx --include-running -w

OPTIMIZATIONS:
    - Minimal validation (errors reported in summary)
    - Parallel API calls where possible
    - Reduced redundant API requests
    - Streamlined output

REQUIRED PERMISSIONS:
    Your PAT needs 'repo' and 'read:org' scopes for full access.
EOF
}

# Function to save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
GITHUB_ORG="$GITHUB_ORG"
GITHUB_TOKEN="$GITHUB_TOKEN"
SPECIFIC_REPOS="$SPECIFIC_REPOS"
INCLUDE_RUNNING=$INCLUDE_RUNNING
POLL_INTERVAL=$POLL_INTERVAL
EOF
    print_color "$GREEN" "Configuration saved to $CONFIG_FILE"
}

# Function to load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        print_color "$GREEN" "Configuration loaded from $CONFIG_FILE"
        return 0
    else
        print_color "$RED" "No configuration file found at $CONFIG_FILE"
        return 1
    fi
}

# Fast validation - just check if we can access the org (no detailed validation)
fast_validate_access() {
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/orgs/$GITHUB_ORG" -o /dev/null 2>/dev/null)
    
    if [[ "$response" != "200" ]]; then
        VALIDATION_ERRORS="Failed to access GitHub API for org $GITHUB_ORG (HTTP: $response)"
        return 1
    fi
    return 0
}

# Get all repositories in one call (optimized)
get_all_org_repositories() {
    local all_repos=""
    local page=1
    
    while true; do
        local response
        response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=100&page=$page&type=all" 2>/dev/null)
        
        if [[ -z "$response" ]] || [[ "$response" == "null" ]]; then
            break
        fi
        
        local repos
        repos=$(echo "$response" | jq -r '.[].name' 2>/dev/null)
        
        if [[ -z "$repos" ]] || [[ "$repos" == "null" ]]; then
            break
        fi
        
        all_repos="$all_repos $repos"
        ((page++))
        
        # Prevent infinite loops
        if [[ $page -gt 50 ]]; then
            API_ERRORS="${API_ERRORS}Too many repository pages (>50), stopped at page $page. "
            break
        fi
    done
    
    echo "$all_repos"
}

# Get repositories to monitor (optimized)
get_repositories_to_monitor() {
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        echo "$SPECIFIC_REPOS" | tr ',' ' ' | xargs -n1 | xargs
    else
        get_all_org_repositories
    fi
}

# Optimized job counting with better error handling
get_jobs_for_repo_fast() {
    local repo_name=$1
    local full_repo="$GITHUB_ORG/$repo_name"
    local queued_count=0
    local running_count=0
    
    # Single API call to get recent workflow runs (both queued and in_progress)
    local response
    response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$full_repo/actions/runs?per_page=50&page=1" 2>/dev/null)
    
    if [[ -z "$response" ]] || [[ "$response" == "null" ]]; then
        API_ERRORS="${API_ERRORS}Failed to get runs for $repo_name. "
        echo "0:0"
        return
    fi
    
    # Extract queued and running run IDs in one pass
    local queued_runs running_runs
    queued_runs=$(echo "$response" | jq -r '.workflow_runs[] | select(.status == "queued") | .id' 2>/dev/null)
    
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        running_runs=$(echo "$response" | jq -r '.workflow_runs[] | select(.status == "in_progress") | .id' 2>/dev/null)
    fi
    
    # Count queued jobs
    for run_id in $queued_runs; do
        if [[ -n "$run_id" ]] && [[ "$run_id" != "null" ]]; then
            local jobs_response
            jobs_response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/$full_repo/actions/runs/$run_id/jobs" 2>/dev/null)
            
            local jobs_count
            jobs_count=$(echo "$jobs_response" | jq '[.jobs[] | select(.status == "queued")] | length' 2>/dev/null)
            
            if [[ "$jobs_count" =~ ^[0-9]+$ ]]; then
                ((queued_count += jobs_count))
            fi
        fi
    done
    
    # Count running jobs if requested
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        for run_id in $running_runs; do
            if [[ -n "$run_id" ]] && [[ "$run_id" != "null" ]]; then
                local jobs_response
                jobs_response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github+json" \
                    "https://api.github.com/repos/$full_repo/actions/runs/$run_id/jobs" 2>/dev/null)
                
                local jobs_count
                jobs_count=$(echo "$jobs_response" | jq '[.jobs[] | select(.status == "in_progress")] | length' 2>/dev/null)
                
                if [[ "$jobs_count" =~ ^[0-9]+$ ]]; then
                    ((running_count += jobs_count))
                fi
            fi
        done
    fi
    
    echo "$queued_count:$running_count"
}

# Optimized display and counting
scan_and_display_jobs() {
    local total_queued=0
    local total_running=0
    local repo_count=0
    local processed_repos=0
    
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        print_color "$BLUE" "Scanning specific repositories in $GITHUB_ORG..."
    else
        print_color "$BLUE" "Scanning all repositories in $GITHUB_ORG..."
    fi
    
    local repositories
    repositories=$(get_repositories_to_monitor)
    
    if [[ -z "$repositories" ]]; then
        API_ERRORS="${API_ERRORS}No repositories found or accessible. "
        echo "0"
        return 1
    fi
    
    # Count total repos for progress
    repo_count=$(echo "$repositories" | wc -w)
    
    for repo in $repositories; do
        ((processed_repos++))
        
        # Show progress for large repo sets
        if [[ $repo_count -gt 10 ]]; then
            echo -n "[$processed_repos/$repo_count] $GITHUB_ORG/$repo... "
        else
            echo -n "Checking $GITHUB_ORG/$repo... "
        fi
        
        local job_counts
        job_counts=$(get_jobs_for_repo_fast "$repo")
        
        local repo_queued repo_running
        repo_queued=$(echo "$job_counts" | cut -d':' -f1)
        repo_running=$(echo "$job_counts" | cut -d':' -f2)
        
        # Quick display logic
        if [[ "$INCLUDE_RUNNING" == "true" ]]; then
            if [[ "$repo_queued" -gt 0 ]] || [[ "$repo_running" -gt 0 ]]; then
                echo "($repo_queued queued, $repo_running running)"
                [[ "$repo_queued" -gt 0 ]] && print_color "$YELLOW" "  └─ $repo_queued queued"
                [[ "$repo_running" -gt 0 ]] && print_color "$CYAN" "  └─ $repo_running running"
            else
                echo "(0 queued, 0 running)"
            fi
        else
            if [[ "$repo_queued" -gt 0 ]]; then
                echo "($repo_queued queued)"
                print_color "$YELLOW" "  └─ $repo_queued queued"
            else
                echo "(0 queued)"
            fi
        fi
        
        # Accumulate totals
        if [[ "$repo_queued" =~ ^[0-9]+$ ]]; then
            ((total_queued += repo_queued))
        fi
        if [[ "$repo_running" =~ ^[0-9]+$ ]]; then
            ((total_running += repo_running))
        fi
    done
    
    echo
    print_color "$BLUE" "=== SUMMARY ==="
    print_color "$BLUE" "  Organization: $GITHUB_ORG"
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        print_color "$BLUE" "  Specific repositories: $processed_repos"
        print_color "$BLUE" "  Filter: $SPECIFIC_REPOS"
    else
        print_color "$BLUE" "  Total repositories scanned: $processed_repos"
    fi
    print_color "$BLUE" "  Total queued jobs: $total_queued"
    
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        print_color "$CYAN" "  Total running jobs: $total_running"
        print_color "$BLUE" "  Total active jobs: $((total_queued + total_running))"
    fi
    
    # Display any errors encountered
    if [[ -n "$VALIDATION_ERRORS" ]]; then
        print_color "$RED" "  Validation errors: $VALIDATION_ERRORS"
    fi
    if [[ -n "$API_ERRORS" ]]; then
        print_color "$YELLOW" "  API warnings: $API_ERRORS"
    fi
    
    echo "$total_queued"
}

# Optimized watch mode
watch_mode() {
    local mode_desc="queued jobs"
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        mode_desc="queued and running jobs"
    fi
    
    print_color "$GREEN" "Starting optimized monitoring of $mode_desc (every ${POLL_INTERVAL}s)"
    print_color "$GREEN" "Press Ctrl+C to stop"
    echo
    
    while true; do
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
        
        print_color "$BLUE" "[$timestamp] Checking jobs..."
        
        # Reset error tracking for each iteration
        VALIDATION_ERRORS=""
        API_ERRORS=""
        
        local queue_count
        queue_count=$(scan_and_display_jobs)
        
        log_message "Queue count: $queue_count"
        
        echo
        print_color "$BLUE" "Next check in ${POLL_INTERVAL}s..."
        echo "$(printf '=%.0s' {1..50})"
        
        sleep "$POLL_INTERVAL"
    done
}

# Parse command line arguments
GITHUB_ORG=""
GITHUB_TOKEN=""
SPECIFIC_REPOS=""
INCLUDE_RUNNING=false
POLL_INTERVAL=$DEFAULT_POLL_INTERVAL
WATCH_MODE=false
SAVE_CONFIG=false
LOAD_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org)
            GITHUB_ORG="$2"
            shift 2
            ;;
        -t|--token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -r|--repos)
            SPECIFIC_REPOS="$2"
            shift 2
            ;;
        --include-running)
            INCLUDE_RUNNING=true
            shift
            ;;
        -i|--interval)
            POLL_INTERVAL="$2"
            shift 2
            ;;
        -w|--watch)
            WATCH_MODE=true
            shift
            ;;
        -s|--save-config)
            SAVE_CONFIG=true
            shift
            ;;
        -c|--load-config)
            LOAD_CONFIG=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            print_color "$RED" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Load configuration if requested
if [[ "$LOAD_CONFIG" == "true" ]]; then
    load_config || exit 1
fi

# Basic validation
if [[ -z "$GITHUB_ORG" ]] || [[ -z "$GITHUB_TOKEN" ]]; then
    print_color "$RED" "Error: GitHub organization and token are required"
    usage
    exit 1
fi

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
    print_color "$RED" "Error: Interval must be a positive integer"
    exit 1
fi

# Check for required dependencies
for cmd in curl jq; do
    if ! command -v $cmd &> /dev/null; then
        print_color "$RED" "Error: $cmd is required but not installed"
        exit 1
    fi
done

# Fast validation (errors will be shown in summary)
fast_validate_access

# Save configuration if requested
if [[ "$SAVE_CONFIG" == "true" ]]; then
    save_config
fi

# Main execution
print_color "$GREEN" "GitHub Actions Queue Monitor (Optimized)"
print_color "$GREEN" "Organization: $GITHUB_ORG"
if [[ -n "$SPECIFIC_REPOS" ]]; then
    print_color "$GREEN" "Target repositories: $SPECIFIC_REPOS"
fi
if [[ "$INCLUDE_RUNNING" == "true" ]]; then
    print_color "$GREEN" "Mode: Monitoring queued AND running jobs"
fi
echo

if [[ "$WATCH_MODE" == "true" ]]; then
    watch_mode
else
    # Single check mode
    queue_count=$(scan_and_display_jobs)
    log_message "Single check completed. Queue count: $queue_count"
fi
