#!/bin/bash

# GitHub Actions Queue Monitor for Self-Hosted Runners
# Author: GitHub Copilot
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
GitHub Actions Queue Monitor

Usage: $0 [OPTIONS]

OPTIONS:
    -o, --org OWNER/ORG         GitHub organization (required)
    -t, --token TOKEN           GitHub Personal Access Token (required)
    -r, --repos REPO1,REPO2     Comma-separated list of specific repositories to monitor
                               (optional - if not provided, monitors all org repos)
    -l, --low-threshold NUM     Low queue threshold (default: $DEFAULT_LOW_THRESHOLD)
    -h, --high-threshold NUM    High queue threshold (default: $DEFAULT_HIGH_THRESHOLD)
    -i, --interval SECONDS      Polling interval for watch mode (default: $DEFAULT_POLL_INTERVAL)
    --include-running           Include running jobs in the analysis and display
    -w, --watch                 Continuous monitoring mode
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

    # Continuous monitoring with custom thresholds and running jobs
    $0 -o myorg -t ghp_xxxxxxxxxxxxxxxxxxxx -r "repo1,repo2" -l 10 -h 30 --include-running -w

    # Save configuration for repeated use (including running jobs flag)
    $0 -o myorg -t ghp_xxxxxxxxxxxxxxxxxxxx --include-running -s

    # Load saved config and watch
    $0 -c -w

REPOSITORY SPECIFICATION:
    - Use repository names only (not full owner/repo format)
    - Separate multiple repositories with commas (no spaces)
    - Example: -r "webapp,api,worker" not -r "myorg/webapp,myorg/api"

RUNNING JOBS:
    - When --include-running is used, running jobs are counted separately
    - Running jobs help assess current runner utilization
    - Total load = queued jobs + running jobs
    - Thresholds still apply only to queued jobs for scaling decisions

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
LOW_THRESHOLD=$LOW_THRESHOLD
HIGH_THRESHOLD=$HIGH_THRESHOLD
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

# Function to validate GitHub token and org
validate_github_access() {
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/orgs/$GITHUB_ORG" -o /tmp/github_test_response 2>/dev/null)
    
    if [[ "$response" != "200" ]]; then
        print_color "$RED" "Failed to access GitHub API. HTTP Status: $response"
        if [[ -f /tmp/github_test_response ]]; then
            print_color "$RED" "Error details: $(cat /tmp/github_test_response)"
        fi
        return 1
    fi
    
    print_color "$GREEN" "✓ GitHub API access validated for organization: $GITHUB_ORG"
    return 0
}

# Function to validate specific repositories exist
validate_specific_repos() {
    local repos_to_check=$1
    local invalid_repos=""
    
    print_color "$BLUE" "Validating specified repositories..."
    
    IFS=',' read -ra REPO_ARRAY <<< "$repos_to_check"
    for repo_name in "${REPO_ARRAY[@]}"; do
        # Trim whitespace
        repo_name=$(echo "$repo_name" | xargs)
        local full_repo="$GITHUB_ORG/$repo_name"
        
        local response
        response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/$full_repo" -o /tmp/repo_check_response 2>/dev/null)
        
        if [[ "$response" != "200" ]]; then
            invalid_repos="$invalid_repos $repo_name"
            print_color "$RED" "  ✗ Repository '$repo_name' not found or not accessible"
        else
            print_color "$GREEN" "  ✓ Repository '$repo_name' validated"
        fi
    done
    
    if [[ -n "$invalid_repos" ]]; then
        print_color "$RED" "Invalid repositories found:$invalid_repos"
        print_color "$RED" "Please check repository names and access permissions."
        return 1
    fi
    
    return 0
}

# Function to get all repositories in the organization
get_org_repositories() {
    local page=1
    local all_repos=""
    
    while true; do
        local response
        response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/orgs/$GITHUB_ORG/repos?per_page=100&page=$page&type=all")
        
        local repos
        repos=$(echo "$response" | jq -r '.[].name' 2>/dev/null)
        
        if [[ -z "$repos" ]] || [[ "$repos" == "null" ]]; then
            break
        fi
        
        all_repos="$all_repos $repos"
        ((page++))
    done
    
    echo "$all_repos"
}

# Function to get repositories to monitor (either specific or all)
get_repositories_to_monitor() {
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        # Convert comma-separated list to space-separated and trim whitespace
        echo "$SPECIFIC_REPOS" | tr ',' ' ' | xargs -n1 | xargs
    else
        get_org_repositories
    fi
}

# Function to get queued and running jobs for a repository
get_jobs_for_repo() {
    local repo_name=$1
    local full_repo="$GITHUB_ORG/$repo_name"
    local queued_count=0
    local running_count=0
    local page=1
    
    # Get queued workflow runs
    while true; do
        local response
        response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/$full_repo/actions/runs?status=queued&per_page=100&page=$page")
        
        local runs
        runs=$(echo "$response" | jq -r '.workflow_runs[]?.id' 2>/dev/null)
        
        if [[ -z "$runs" ]] || [[ "$runs" == "null" ]]; then
            break
        fi
        
        # Count jobs in each queued run
        for run_id in $runs; do
            local jobs_response
            jobs_response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/$full_repo/actions/runs/$run_id/jobs?filter=latest")
            
            local queued_jobs_in_run
            queued_jobs_in_run=$(echo "$jobs_response" | jq '[.jobs[] | select(.status == "queued")] | length' 2>/dev/null)
            
            if [[ "$queued_jobs_in_run" =~ ^[0-9]+$ ]]; then
                ((queued_count += queued_jobs_in_run))
            fi
        done
        
        ((page++))
    done
    
    # Get running workflow runs if requested
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        page=1
        while true; do
            local response
            response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/repos/$full_repo/actions/runs?status=in_progress&per_page=100&page=$page")
            
            local runs
            runs=$(echo "$response" | jq -r '.workflow_runs[]?.id' 2>/dev/null)
            
            if [[ -z "$runs" ]] || [[ "$runs" == "null" ]]; then
                break
            fi
            
            # Count jobs in each running run
            for run_id in $runs; do
                local jobs_response
                jobs_response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github+json" \
                    "https://api.github.com/repos/$full_repo/actions/runs/$run_id/jobs?filter=latest")
                
                local running_jobs_in_run
                running_jobs_in_run=$(echo "$jobs_response" | jq '[.jobs[] | select(.status == "in_progress")] | length' 2>/dev/null)
                
                if [[ "$running_jobs_in_run" =~ ^[0-9]+$ ]]; then
                    ((running_count += running_jobs_in_run))
                fi
            done
            
            ((page++))
        done
    fi
    
    echo "$queued_count:$running_count"
}

# Function to get total queued jobs (returns only the number, no display)
get_total_queued_jobs() {
    local total_queued=0
    
    local repositories
    repositories=$(get_repositories_to_monitor)
    
    if [[ -z "$repositories" ]]; then
        echo "0"
        return 1
    fi
    
    for repo in $repositories; do
        local job_counts
        job_counts=$(get_jobs_for_repo "$repo")
        
        local repo_queued
        repo_queued=$(echo "$job_counts" | cut -d':' -f1)
        
        if [[ "$repo_queued" =~ ^[0-9]+$ ]]; then
            ((total_queued += repo_queued))
        fi
    done
    
    # Return ONLY the numeric result
    echo "$total_queued"
}

# Function to display scan results (separate from counting)
display_scan_results() {
    local total_queued=0
    local total_running=0
    local repo_count=0
    
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        print_color "$BLUE" "Scanning specific repositories in $GITHUB_ORG..."
        print_color "$BLUE" "Target repositories: $SPECIFIC_REPOS"
    else
        print_color "$BLUE" "Scanning all repositories in $GITHUB_ORG..."
    fi
    
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        print_color "$BLUE" "Including running jobs in analysis"
    fi
    
    local repositories
    repositories=$(get_repositories_to_monitor)
    
    if [[ -z "$repositories" ]]; then
        if [[ -n "$SPECIFIC_REPOS" ]]; then
            print_color "$RED" "No valid repositories found from specified list"
        else
            print_color "$RED" "No repositories found or access denied"
        fi
        return 1
    fi
    
    for repo in $repositories; do
        ((repo_count++))
        echo -n "Checking $GITHUB_ORG/$repo... "
        
        local job_counts
        job_counts=$(get_jobs_for_repo "$repo")
        
        local repo_queued repo_running
        repo_queued=$(echo "$job_counts" | cut -d':' -f1)
        repo_running=$(echo "$job_counts" | cut -d':' -f2)
        
        if [[ "$INCLUDE_RUNNING" == "true" ]]; then
            if [[ "$repo_queued" -gt 0 ]] || [[ "$repo_running" -gt 0 ]]; then
                echo "($repo_queued queued, $repo_running running)"
                if [[ "$repo_queued" -gt 0 ]]; then
                    print_color "$YELLOW" "  └─ $GITHUB_ORG/$repo: $repo_queued queued jobs"
                fi
                if [[ "$repo_running" -gt 0 ]]; then
                    print_color "$CYAN" "  └─ $GITHUB_ORG/$repo: $repo_running running jobs"
                fi
            else
                echo "(0 queued, 0 running)"
            fi
        else
            if [[ "$repo_queued" -gt 0 ]]; then
                echo "($repo_queued queued)"
                print_color "$YELLOW" "  └─ $GITHUB_ORG/$repo: $repo_queued queued jobs"
            else
                echo "(0 queued)"
            fi
        fi
        
        if [[ "$repo_queued" =~ ^[0-9]+$ ]]; then
            ((total_queued += repo_queued))
        fi
        if [[ "$repo_running" =~ ^[0-9]+$ ]]; then
            ((total_running += repo_running))
        fi
    done
    
    echo
    print_color "$BLUE" "Summary:"
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        print_color "$BLUE" "  Specific repositories scanned: $repo_count"
        print_color "$BLUE" "  Repository filter: $SPECIFIC_REPOS"
    else
        print_color "$BLUE" "  All repositories scanned: $repo_count"
    fi
    print_color "$BLUE" "  Total queued jobs: $total_queued"
    
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        print_color "$CYAN" "  Total running jobs: $total_running"
        print_color "$BLUE" "  Total active jobs (queued + running): $((total_queued + total_running))"
    fi
}

# Function to provide scaling recommendations
provide_recommendations() {
    local queue_count=$1
    
    echo
    print_color "$BLUE" "=== SCALING RECOMMENDATIONS ==="
    
    if [[ $queue_count -eq 0 ]]; then
        print_color "$GREEN" "✓ No queued jobs - runners are keeping up with demand"
        print_color "$GREEN" "  Recommendation: Current capacity is sufficient"
    elif [[ $queue_count -lt $LOW_THRESHOLD ]]; then
        print_color "$GREEN" "✓ Queue is manageable ($queue_count < $LOW_THRESHOLD)"
        print_color "$GREEN" "  Recommendation: Monitor but no immediate action needed"
    elif [[ $queue_count -lt $HIGH_THRESHOLD ]]; then
        print_color "$YELLOW" "⚠ Queue is building up ($queue_count >= $LOW_THRESHOLD)"
        print_color "$YELLOW" "  Recommendation: Consider scaling up runners soon"
    else
        print_color "$RED" "🚨 High queue detected ($queue_count >= $HIGH_THRESHOLD)"
        print_color "$RED" "  Recommendation: SCALE UP IMMEDIATELY - jobs are backing up"
    fi
    
    echo
    print_color "$BLUE" "Configuration:"
    print_color "$BLUE" "  Organization: $GITHUB_ORG"
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        print_color "$BLUE" "  Monitoring specific repos: $SPECIFIC_REPOS"
    else
        print_color "$BLUE" "  Monitoring: All organization repositories"
    fi
    print_color "$BLUE" "  Include running jobs: $INCLUDE_RUNNING"
    print_color "$BLUE" "  Low threshold (monitor): $LOW_THRESHOLD"
    print_color "$BLUE" "  High threshold (scale up): $HIGH_THRESHOLD"
    print_color "$BLUE" "  Current queue count: $queue_count"
    
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        print_color "$BLUE" "  Note: Scaling decisions based on queued jobs only"
        print_color "$BLUE" "        Running jobs indicate current runner utilization"
    fi
}

# Function for continuous monitoring
watch_mode() {
    local mode_desc="queued jobs"
    if [[ "$INCLUDE_RUNNING" == "true" ]]; then
        mode_desc="queued and running jobs"
    fi
    
    print_color "$GREEN" "Starting continuous monitoring of $mode_desc (polling every ${POLL_INTERVAL}s)"
    print_color "$GREEN" "Press Ctrl+C to stop"
    echo
    
    while true; do
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC')
        
        print_color "$BLUE" "[$timestamp] Checking queue..."
        
        # Display the scan results
        display_scan_results
        
        # Get the numeric count separately
        local queue_count
        queue_count=$(get_total_queued_jobs)
        
        if [[ -n "$SPECIFIC_REPOS" ]]; then
            log_message "Queue count for repos [$SPECIFIC_REPOS]: $queue_count (include_running: $INCLUDE_RUNNING)"
        else
            log_message "Queue count (all repos): $queue_count (include_running: $INCLUDE_RUNNING)"
        fi
        
        provide_recommendations "$queue_count"
        
        echo
        print_color "$BLUE" "Next check in ${POLL_INTERVAL}s..."
        echo "----------------------------------------"
        
        sleep "$POLL_INTERVAL"
    done
}

# Parse command line arguments
GITHUB_ORG=""
GITHUB_TOKEN=""
SPECIFIC_REPOS=""
INCLUDE_RUNNING=false
LOW_THRESHOLD=$DEFAULT_LOW_THRESHOLD
HIGH_THRESHOLD=$DEFAULT_HIGH_THRESHOLD
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
        -l|--low-threshold)
            LOW_THRESHOLD="$2"
            shift 2
            ;;
        -h|--high-threshold)
            HIGH_THRESHOLD="$2"
            shift 2
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
    if ! load_config; then
        exit 1
    fi
fi

# Validate required parameters
if [[ -z "$GITHUB_ORG" ]]; then
    print_color "$RED" "Error: GitHub organization is required"
    usage
    exit 1
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
    print_color "$RED" "Error: GitHub Personal Access Token is required"
    usage
    exit 1
fi

# Validate numeric thresholds
if ! [[ "$LOW_THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$HIGH_THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
    print_color "$RED" "Error: Thresholds and interval must be positive integers"
    exit 1
fi

if [[ $LOW_THRESHOLD -ge $HIGH_THRESHOLD ]]; then
    print_color "$RED" "Error: Low threshold must be less than high threshold"
    exit 1
fi

# Check for required dependencies
for cmd in curl jq; do
    if ! command -v $cmd &> /dev/null; then
        print_color "$RED" "Error: $cmd is required but not installed"
        exit 1
    fi
done

# Validate GitHub access
if ! validate_github_access; then
    exit 1
fi

# Validate specific repositories if provided
if [[ -n "$SPECIFIC_REPOS" ]]; then
    if ! validate_specific_repos "$SPECIFIC_REPOS"; then
        exit 1
    fi
fi

# Save configuration if requested
if [[ "$SAVE_CONFIG" == "true" ]]; then
    save_config
fi

# Main execution
print_color "$GREEN" "GitHub Actions Queue Monitor"
print_color "$GREEN" "Organization: $GITHUB_ORG"
if [[ -n "$SPECIFIC_REPOS" ]]; then
    print_color "$GREEN" "Target repositories: $SPECIFIC_REPOS"
else
    print_color "$GREEN" "Monitoring: All organization repositories"
fi
if [[ "$INCLUDE_RUNNING" == "true" ]]; then
    print_color "$GREEN" "Mode: Monitoring queued AND running jobs"
else
    print_color "$GREEN" "Mode: Monitoring queued jobs only"
fi
print_color "$GREEN" "Monitoring thresholds: Low=$LOW_THRESHOLD, High=$HIGH_THRESHOLD"
echo

if [[ "$WATCH_MODE" == "true" ]]; then
    watch_mode
else
    # Single check mode
    # Display the scan results
    display_scan_results
    
    # Get the numeric count separately
    queue_count=$(get_total_queued_jobs)
    
    provide_recommendations "$queue_count"
    if [[ -n "$SPECIFIC_REPOS" ]]; then
        log_message "Single check completed for repos [$SPECIFIC_REPOS]. Queue count: $queue_count (include_running: $INCLUDE_RUNNING)"
    else
        log_message "Single check completed (all repos). Queue count: $queue_count (include_running: $INCLUDE_RUNNING)"
    fi
fi
