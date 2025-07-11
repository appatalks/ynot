#!/bin/bash
# Simplified Repository File Size Analysis for GitHub Enterprise Server
# A clean, maintainable version that provides the same reporting functionality

# Default configuration
SIZE_MIN_MB=${SIZE_MIN_MB:-1}
SIZE_MAX_MB=${SIZE_MAX_MB:-25}
MAX_REPOS=${MAX_REPOS:-100}
MAX_OBJECTS=${MAX_OBJECTS:-10}
INCLUDE_DELETED=${INCLUDE_DELETED:-false}
REPO_BASE=${REPO_BASE:-"/data/user/repositories"}
DEBUG=${DEBUG:-false}

# Output files
OVER_MAX_FILE="/tmp/repos_over_${SIZE_MAX_MB}mb.txt"
BETWEEN_FILE="/tmp/repos_${SIZE_MIN_MB}mb_to_${SIZE_MAX_MB}mb.txt"

# Help function
show_help() {
    cat << EOF
Simplified Repository File Size Analysis
========================================
Usage: bash $0 [options]

Options:
  -h, --help                Show this help message
  -m, --min-size <MB>       Minimum file size in MB (default: $SIZE_MIN_MB)
  -M, --max-size <MB>       Maximum file size in MB (default: $SIZE_MAX_MB)
  -r, --max-repos <N>       Max repositories to analyze (default: $MAX_REPOS)
  -o, --max-objects <N>     Max objects per repository (default: $MAX_OBJECTS)
  -d, --include-deleted     Include deleted repositories (default: $INCLUDE_DELETED)
  -b, --base-path <PATH>    Repository base path (default: $REPO_BASE)
  --debug                   Enable debug output

Environment Variables:
  SIZE_MIN_MB, SIZE_MAX_MB, MAX_REPOS, MAX_OBJECTS, INCLUDE_DELETED, REPO_BASE, DEBUG

Note: Script automatically uses sudo for repository access when needed

Example:
  bash $0 --min-size 1 --max-size 25 --max-repos 50
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -m|--min-size) SIZE_MIN_MB=$2; shift 2 ;;
        -M|--max-size) SIZE_MAX_MB=$2; shift 2 ;;
        -r|--max-repos) MAX_REPOS=$2; shift 2 ;;
        -o|--max-objects) MAX_OBJECTS=$2; shift 2 ;;
        -d|--include-deleted) INCLUDE_DELETED=true; shift ;;
        -b|--base-path) REPO_BASE=$2; shift 2 ;;
        --debug) DEBUG=true; shift ;;
        *) echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
    esac
done

# Function to check if we can access repository directory
check_repo_access() {
    if [[ ! -d "$REPO_BASE" ]]; then
        echo "Error: Repository base path not found: $REPO_BASE"
        echo "Set REPO_BASE environment variable to the correct path"
        return 1
    fi
    
    # Test if we can read the repository directory with sudo
    if ! sudo ls "$REPO_BASE" >/dev/null 2>&1; then
        echo "Error: Cannot access $REPO_BASE even with sudo"
        echo "Please check that the path exists and you have permission to use sudo"
        return 1
    fi
    
    return 0
}

# Check repository access
if ! check_repo_access; then
    exit 1
fi

# Convert sizes to bytes for calculations
SIZE_MIN_BYTES=$((SIZE_MIN_MB * 1024 * 1024))
SIZE_MAX_BYTES=$((SIZE_MAX_MB * 1024 * 1024))

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
    
    # Handle compressed /nw/ format paths
    if [[ "$repo_name" =~ ^[0-9a-f]/nw/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]+/[0-9a-f]+$ ]]; then
        # This is a compressed path, keep as-is or try to resolve
        echo "$repo_name"
    else
        echo "$repo_name"
    fi
}

# Function to process a single repository
process_repository() {
    local repo_path=$1
    local repo_num=$2
    local total_repos=$3
    local repo_name
    
    repo_name=$(get_repo_name "$repo_path")
    echo "[$repo_num/$total_repos] Checking $repo_name..."
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: Repository path: $repo_path"
        echo "DEBUG: SIZE_MIN_BYTES: $SIZE_MIN_BYTES, SIZE_MAX_BYTES: $SIZE_MAX_BYTES"
    fi
    
    # Find large files in the repository
    local found_files=0
    
    # Use a single find command to get all files, then filter by size
    # This is more reliable than complex find expressions with -prune
    while IFS= read -r -d '' file; do
        if sudo test -f "$file"; then
            local file_size
            file_size=$(sudo stat -c '%s' "$file" 2>/dev/null) || continue
            
            if [[ "$DEBUG" == "true" ]] && (( file_size >= SIZE_MIN_BYTES )); then
                echo "DEBUG: Found large file $file size: $file_size bytes"
            fi
            
            if (( file_size >= SIZE_MIN_BYTES )); then
                local size_display
                size_display=$(get_human_size "$file_size")
                local relative_path
                relative_path=$(echo "$file" | sed "s|$repo_path/||")
                
                if (( file_size > SIZE_MAX_BYTES )); then
                    echo "$repo_name:$relative_path ($size_display)" >> "$OVER_MAX_FILE"
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Added to over-max: $repo_name:$relative_path ($size_display)"
                else
                    echo "$repo_name:$relative_path ($size_display)" >> "$BETWEEN_FILE"
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Added to between: $repo_name:$relative_path ($size_display)"
                fi
                ((found_files++))
                
                if (( found_files >= MAX_OBJECTS )); then
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Reached max objects limit ($MAX_OBJECTS) for $repo_name"
                    break
                fi
            fi
        fi
    done < <(sudo find "$repo_path" -type f -print0 2>/dev/null)
    
    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found $found_files large files in $repo_name"
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
total_size=$(sudo du -sh "$REPO_BASE" 2>/dev/null | cut -f1)
echo "Initial estimate: $total_size	$REPO_BASE"

echo "Scanning for repositories..."

# Find all Git repositories
mapfile -t all_repos < <(sudo find "$REPO_BASE" -name "*.git" -type d 2>/dev/null | head -1000)

# Filter repositories if not including deleted ones
repos_to_analyze=()
for repo in "${all_repos[@]}"; do
    # Robust filter for deleted repositories (similar to original script)
    if [[ "$INCLUDE_DELETED" == "false" ]]; then
        # Check if repository has objects directory with pack files - reliable heuristic for active repos
        if ! sudo test -d "$repo/objects" || ! sudo find "$repo" -type f -name "*.pack" 2>/dev/null | grep -q .; then
            continue
        fi
    fi
    repos_to_analyze+=("$repo")
done

total_found=${#repos_to_analyze[@]}
total_all=${#all_repos[@]}

if [[ "$INCLUDE_DELETED" == "false" ]]; then
    excluded=$((total_all - total_found))
    echo "Found $total_found active repositories after filtering (excluded $excluded deleted/empty repositories)"
else
    echo "Found $total_found repositories (no filtering applied)"
fi

if (( total_found == 0 )); then
    echo "No repositories found to analyze."
    exit 0
fi

echo "Performing initial size scan to identify largest repositories..."

# Get repository sizes and sort by largest
declare -A repo_sizes
temp_size_file=$(mktemp)

for repo in "${repos_to_analyze[@]}"; do
    size_kb=$(sudo du -sk "$repo" 2>/dev/null | cut -f1)
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
    size_kb=$(sudo du -sk "$repo" 2>/dev/null | cut -f1)
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
