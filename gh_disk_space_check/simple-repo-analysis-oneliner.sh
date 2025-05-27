#!/bin/bash
# One-liner compatible version of simple-repo-analysis.sh
# This version includes all functionality in a single script for easy remote execution

# Default configuration - can be overridden by environment variables
SIZE_MIN_MB=${SIZE_MIN_MB:-1}
SIZE_MAX_MB=${SIZE_MAX_MB:-25}
MAX_REPOS=${MAX_REPOS:-100}
MAX_OBJECTS=${MAX_OBJECTS:-10}
INCLUDE_DELETED=${INCLUDE_DELETED:-false}
REPO_BASE=${REPO_BASE:-"/data/user/repositories"}

# Parse any command line arguments passed through curl
while [[ $# -gt 0 ]]; do
    case $1 in
        --min-size) SIZE_MIN_MB=$2; shift 2 ;;
        --max-size) SIZE_MAX_MB=$2; shift 2 ;;
        --max-repos) MAX_REPOS=$2; shift 2 ;;
        --max-objects) MAX_OBJECTS=$2; shift 2 ;;
        --include-deleted) INCLUDE_DELETED=true; shift ;;
        --base-path) REPO_BASE=$2; shift 2 ;;
        --help) 
            echo "Simplified Repository File Size Analysis for GHES"
            echo "Usage: sudo bash <(curl -sL URL) [options]"
            echo "Environment variables: SIZE_MIN_MB, SIZE_MAX_MB, MAX_REPOS, MAX_OBJECTS, INCLUDE_DELETED, REPO_BASE"
            exit 0 ;;
        *) shift ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Validate repository base path
if [[ ! -d "$REPO_BASE" ]]; then
    echo "Error: Repository base path not found: $REPO_BASE"
    echo "Set REPO_BASE environment variable to the correct path"
    exit 1
fi

# Convert sizes to bytes for calculations
SIZE_MIN_BYTES=$((SIZE_MIN_MB * 1024 * 1024))
SIZE_MAX_BYTES=$((SIZE_MAX_MB * 1024 * 1024))

# Output files
OVER_MAX_FILE="/tmp/repos_over_${SIZE_MAX_MB}mb.txt"
BETWEEN_FILE="/tmp/repos_${SIZE_MIN_MB}mb_to_${SIZE_MAX_MB}mb.txt"

# Initialize output files
> "$OVER_MAX_FILE"
> "$BETWEEN_FILE"

# Function to get human-readable file size
get_human_size() {
    local size_bytes=$1
    if (( size_bytes >= 1073741824 )); then
        echo "$(echo "scale=2; $size_bytes/1073741824" | bc)GB"
    elif (( size_bytes >= 1048576 )); then
        echo "$(echo "scale=2; $size_bytes/1048576" | bc)MB"
    else
        echo "$(echo "scale=2; $size_bytes/1024" | bc)KB"
    fi
}

# Function to get repository display name
get_repo_name() {
    local repo_path=$1
    local repo_name
    
    # Try to get friendly name using ghe-nwo if available
    if command -v ghe-nwo &> /dev/null; then
        repo_name=$(ghe-nwo "$repo_path" 2>/dev/null)
        if [[ -n "$repo_name" ]]; then
            echo "$repo_name"
            return
        fi
    fi
    
    # Fallback to path-based name extraction
    repo_name=$(echo "$repo_path" | sed "s|$REPO_BASE/||g" | sed 's|\.git$||g')
    echo "$repo_name"
}

# Function to process a single repository
process_repository() {
    local repo_path=$1
    local repo_num=$2
    local total_repos=$3
    local repo_name
    
    repo_name=$(get_repo_name "$repo_path")
    echo "[$repo_num/$total_repos] Checking $repo_name..."
    
    # Find large files in the repository
    local pack_dir="$repo_path/objects/pack"
    local found_files=0
    
    # Check pack files first (most likely to be large)
    if [[ -d "$pack_dir" ]]; then
        while IFS= read -r -d '' pack_file; do
            if [[ -f "$pack_file" ]]; then
                local file_size
                file_size=$(stat -c '%s' "$pack_file" 2>/dev/null) || continue
                
                if (( file_size >= SIZE_MIN_BYTES )); then
                    local size_display
                    size_display=$(get_human_size "$file_size")
                    local relative_path
                    relative_path=$(echo "$pack_file" | sed "s|$repo_path/||")
                    
                    if (( file_size > SIZE_MAX_BYTES )); then
                        echo "$repo_name:$relative_path ($size_display)" >> "$OVER_MAX_FILE"
                    else
                        echo "$repo_name:$relative_path ($size_display)" >> "$BETWEEN_FILE"
                    fi
                    ((found_files++))
                    
                    if (( found_files >= MAX_OBJECTS )); then
                        break
                    fi
                fi
            fi
        done < <(find "$pack_dir" -name "*.pack" -type f -print0 2>/dev/null)
    fi
    
    # Check other large files (excluding pack directory)
    if (( found_files < MAX_OBJECTS )); then
        while IFS= read -r -d '' file; do
            if [[ -f "$file" ]]; then
                local file_size
                file_size=$(stat -c '%s' "$file" 2>/dev/null) || continue
                
                if (( file_size >= SIZE_MIN_BYTES )); then
                    local size_display
                    size_display=$(get_human_size "$file_size")
                    local relative_path
                    relative_path=$(echo "$file" | sed "s|$repo_path/||")
                    
                    if (( file_size > SIZE_MAX_BYTES )); then
                        echo "$repo_name:$relative_path ($size_display)" >> "$OVER_MAX_FILE"
                    else
                        echo "$repo_name:$relative_path ($size_display)" >> "$BETWEEN_FILE"
                    fi
                    ((found_files++))
                    
                    if (( found_files >= MAX_OBJECTS )); then
                        break
                    fi
                fi
            fi
        done < <(find "$repo_path" -path "$pack_dir" -prune -o -type f -size "+${SIZE_MIN_MB}M" -print0 2>/dev/null)
    fi
}

# Main analysis
echo "ANALYSIS SETTINGS:"
echo "- Minimum file size: ${SIZE_MIN_MB}MB"
echo "- Maximum file size: ${SIZE_MAX_MB}MB"
echo "- Max repositories to analyze in detail: $MAX_REPOS"
echo "- Max objects per repository: $MAX_OBJECTS"
echo "- Include deleted repositories: $INCLUDE_DELETED"
echo ""

echo "Analyzing repositories in $REPO_BASE..."

# Get initial size estimate
total_size=$(du -sh "$REPO_BASE" 2>/dev/null | cut -f1)
echo "Initial estimate: $total_size	$REPO_BASE"

echo "Scanning for repositories..."

# Find all Git repositories
mapfile -t all_repos < <(find "$REPO_BASE" -name "*.git" -type d 2>/dev/null | head -1000)

# Filter repositories if not including deleted ones
repos_to_analyze=()
for repo in "${all_repos[@]}"; do
    if [[ "$INCLUDE_DELETED" == "false" ]]; then
        # Skip if repository seems deleted
        if [[ -f "$repo/DELETED" ]] || [[ -f "$repo/.deleted" ]]; then
            continue
        fi
    fi
    repos_to_analyze+=("$repo")
done

total_found=${#repos_to_analyze[@]}
echo "Found $total_found active repositories after filtering"

if (( total_found == 0 )); then
    echo "No repositories found to analyze."
    exit 0
fi

echo "Performing initial size scan to identify largest repositories..."

# Get repository sizes and sort by largest
temp_size_file=$(mktemp)
for repo in "${repos_to_analyze[@]}"; do
    size_kb=$(du -sk "$repo" 2>/dev/null | cut -f1)
    if [[ -n "$size_kb" ]] && (( size_kb > 0 )); then
        echo "$size_kb $repo" >> "$temp_size_file"
    fi
done

# Sort by size (largest first) and take top repositories
mapfile -t top_repos < <(sort -rn "$temp_size_file" | head -n "$MAX_REPOS" | cut -d' ' -f2-)
rm -f "$temp_size_file"

# Calculate total storage
total_storage_kb=0
for repo in "${repos_to_analyze[@]}"; do
    size_kb=$(du -sk "$repo" 2>/dev/null | cut -f1)
    if [[ -n "$size_kb" ]]; then
        ((total_storage_kb += size_kb))
    fi
done

total_storage_gb=$(echo "scale=2; $total_storage_kb/1024/1024" | bc)
echo "Total repository storage: $total_storage_gb GB across $total_found repositories"

# Analyze top repositories
repos_to_process=${#top_repos[@]}
echo "Starting repository analysis..."

for i in "${!top_repos[@]}"; do
    process_repository "${top_repos[$i]}" $((i + 1)) "$repos_to_process"
done

# Generate summary report
echo ""
echo "======================================"
echo "REPOSITORY FILE SIZE ANALYSIS SUMMARY"
echo "======================================"
echo "Total repositories found: $total_found"
echo ""

# Count results
over_max_repos=$(awk -F: '{print $1}' "$OVER_MAX_FILE" 2>/dev/null | sort -u | wc -l)
between_repos=$(awk -F: '{print $1}' "$BETWEEN_FILE" 2>/dev/null | sort -u | wc -l)
over_max_files=$(wc -l < "$OVER_MAX_FILE" 2>/dev/null || echo 0)
between_files=$(wc -l < "$BETWEEN_FILE" 2>/dev/null || echo 0)

echo "FINDINGS SUMMARY:"
echo "----------------"
echo "1. Repositories with files > ${SIZE_MAX_MB}MB: $over_max_repos"
echo "   Total files > ${SIZE_MAX_MB}MB: $over_max_files"
echo ""
echo "2. Repositories with files ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $between_repos"
echo "   Total files ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $between_files"
echo ""

# Show top repositories with large files
if (( over_max_repos > 0 )); then
    echo "TOP 5 REPOSITORIES WITH LARGEST FILES:"
    echo "------------------------------------"
    awk -F: '{print $1}' "$OVER_MAX_FILE" | sort | uniq -c | sort -nr | head -5 | \
    while read -r count repo; do
        echo "  $repo: $count large files"
    done
    echo ""
fi

echo "REPORTS LOCATION:"
echo "---------------"
echo "* Files over ${SIZE_MAX_MB}MB: $OVER_MAX_FILE"
echo "* Files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $BETWEEN_FILE"
echo ""
echo "Analysis completed: $(date)"
