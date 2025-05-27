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
DEBUG=${DEBUG:-false}

# Parse any command line arguments passed through curl
while [[ $# -gt 0 ]]; do
    case $1 in
        --min-size) SIZE_MIN_MB=$2; shift 2 ;;
        --max-size) SIZE_MAX_MB=$2; shift 2 ;;
        --max-repos) MAX_REPOS=$2; shift 2 ;;
        --max-objects) MAX_OBJECTS=$2; shift 2 ;;
        --include-deleted) INCLUDE_DELETED=true; shift ;;
        --base-path) REPO_BASE=$2; shift 2 ;;
        --debug) DEBUG=true; shift ;;
        --help) 
            echo "Simplified Repository File Size Analysis for GHES"
            echo "Usage: bash <(curl -sL URL) [options]"
            echo "Environment variables: SIZE_MIN_MB, SIZE_MAX_MB, MAX_REPOS, MAX_OBJECTS, INCLUDE_DELETED, REPO_BASE"
            echo "Note: Script automatically uses sudo for repository access when needed"
            exit 0 ;;
        *) shift ;;
    esac
done

# Convert sizes to bytes for calculations
SIZE_MIN_BYTES=$((SIZE_MIN_MB * 1024 * 1024))
SIZE_MAX_BYTES=$((SIZE_MAX_MB * 1024 * 1024))

# Output files
OVER_MAX_FILE="/tmp/repos_over_${SIZE_MAX_MB}mb.txt"
BETWEEN_FILE="/tmp/repos_${SIZE_MIN_MB}mb_to_${SIZE_MAX_MB}mb.txt"

# Initialize output files
> "$OVER_MAX_FILE"
> "$BETWEEN_FILE"

# Initialize repository name cache
declare -A repo_name_cache

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
    
    # Check if we have this repository in our cache
    if [[ -n "${repo_name_cache[$repo_path]}" ]]; then
        echo "${repo_name_cache[$repo_path]}"
        return
    fi
    
    # For standard scanning, use only path-based name extraction
    # ghe-nwo will only be called for top repositories in the final report
    repo_name=$(echo "$repo_path" | sed "s|$REPO_BASE/||g" | sed 's|\.git$||g')
    # Cache the name
    repo_name_cache["$repo_path"]="$repo_name"
    echo "$repo_name"
}

# We no longer need this function as we're doing name resolution directly
# Function left empty for compatibility with any existing calls
batch_resolve_repo_names() {
    : # Do nothing
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
    
    # First check if repository contains any files
    local file_count
    file_count=$(sudo find "$repo_path" -type f -name "*" | wc -l)
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: Repository $repo_path contains $file_count files"
    fi
    
    if (( file_count == 0 )); then
        echo "  No files found in repository"
        return
    fi
    
    # Use a single find command to get all files, then filter by size
    # This is more reliable than complex find expressions with -prune
    while IFS= read -r -d '' file; do
        if sudo test -f "$file"; then
            local file_size
            file_size=$(sudo stat -c '%s' "$file" 2>/dev/null) || continue
            
            if [[ "$DEBUG" == "true" ]] && (( file_size >= SIZE_MIN_BYTES )); then
                echo "DEBUG: Found large file $file size: $file_size bytes ($(get_human_size "$file_size"))"
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
    if [[ "$INCLUDE_DELETED" == "false" ]]; then
        # Skip if repository seems deleted - check for objects directory with pack files
        # This is a more reliable heuristic for active repositories in GHES
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

echo "Performing file scan on all active repositories..."

# First, we'll scan all repositories for large files directly
echo "PHASE 1: Quick scan of all repositories for large files..."
total_storage_kb=0
repos_scanned=0

for repo in "${repos_to_analyze[@]}"; do
    repos_scanned=$((repos_scanned + 1))
    
    # Get repository size for total statistics
    size_kb=$(sudo du -sk "$repo" 2>/dev/null | cut -f1)
    if [[ -n "$size_kb" ]] && (( size_kb > 0 )); then
        ((total_storage_kb += size_kb))
    fi
    
    # Progress indicator every 10 repositories
    if (( repos_scanned % 10 == 0 )); then
        echo "  Progress: Scanned $repos_scanned/$total_found repositories..."
    fi
    
    # Quick scan for large files using find with -size option
    repo_name=$(get_repo_name "$repo")
    
    # Find files larger than minimum size
    min_size_find=$(( SIZE_MIN_MB * 1024 ))  # Convert to KB for find command
    max_size_find=$(( SIZE_MAX_MB * 1024 ))  # Convert to KB for find command
    
    # Find files larger than max size directly
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: Scanning $repo for files larger than ${SIZE_MAX_MB}MB"
    fi
    
    sudo find "$repo" -type f -size +${max_size_find}k -print0 2>/dev/null | 
    while IFS= read -r -d '' file; do
        size_bytes=$(sudo stat -c '%s' "$file" 2>/dev/null) || continue
        size_display=$(get_human_size "$size_bytes")
        relative_path=$(echo "$file" | sed "s|$repo/||")
        echo "$repo_name:$relative_path ($size_display)" >> "$OVER_MAX_FILE"
        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found large file (over max): $file ($size_display)"
    done
    
    # Find files between min and max size
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: Scanning $repo for files between ${SIZE_MIN_MB}MB and ${SIZE_MAX_MB}MB"
    fi
    
    sudo find "$repo" -type f -size +${min_size_find}k -size -${max_size_find}k -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
        size_bytes=$(sudo stat -c '%s' "$file" 2>/dev/null) || continue
        size_display=$(get_human_size "$size_bytes")
        relative_path=$(echo "$file" | sed "s|$repo/||")
        echo "$repo_name:$relative_path ($size_display)" >> "$BETWEEN_FILE"
        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found large file (between): $file ($size_display)"
    done
done

total_storage_gb=$(echo "scale=2; $total_storage_kb/1024/1024" | bc)
echo "Total repository storage: $total_storage_gb GB across $total_found repositories"

# For detailed analysis, select the top MAX_REPOS largest repositories
echo "PHASE 2: Detailed analysis of largest repositories..."
temp_size_file=$(mktemp)

# Get list of largest repositories for detailed analysis
for repo in "${repos_to_analyze[@]}"; do
    size_kb=$(sudo du -sk "$repo" 2>/dev/null | cut -f1)
    if [[ -n "$size_kb" ]] && (( size_kb > 0 )); then
        echo "$size_kb $repo" >> "$temp_size_file"
    fi
done

if [[ -s "$temp_size_file" ]]; then
    # Sort by size (largest first) and take top repositories
    mapfile -t top_repos < <(sort -rn "$temp_size_file" | head -n "$MAX_REPOS" | cut -d' ' -f2-)
else
    top_repos=()
fi

rm -f "$temp_size_file"
repos_to_process=${#top_repos[@]}

echo "Performing detailed analysis on top $repos_to_process largest repositories..."

if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Selected repositories for analysis:"
    for i in "${!top_repos[@]}"; do
        repo_size_kb=$(sudo du -sk "${top_repos[$i]}" 2>/dev/null | cut -f1)
        repo_size_mb=$(echo "scale=2; $repo_size_kb/1024" | bc)
        echo "DEBUG: $((i + 1)). ${top_repos[$i]} (${repo_size_mb}MB)"
    done
fi

# Skip detailed analysis unless debug is enabled - we already have the data from Phase 1
if [[ "$DEBUG" == "true" ]] && (( repos_to_process > 0 )); then
    echo "Running detailed analysis on top repositories with debug enabled..."
    # Analyze top repositories for large files
    for i in "${!top_repos[@]}"; do
        process_repository "${top_repos[$i]}" $((i + 1)) "$repos_to_process"
    done
else
    echo "Skipping detailed analysis - already collected data in Phase 1"
fi

# First deduplicate the output files to avoid counting repositories multiple times
echo "Deduplicating result files..."
if [[ -s "$OVER_MAX_FILE" ]]; then
    sort -u "$OVER_MAX_FILE" > "${OVER_MAX_FILE}.tmp" && mv "${OVER_MAX_FILE}.tmp" "$OVER_MAX_FILE"
fi

if [[ -s "$BETWEEN_FILE" ]]; then
    sort -u "$BETWEEN_FILE" > "${BETWEEN_FILE}.tmp" && mv "${BETWEEN_FILE}.tmp" "$BETWEEN_FILE"
fi

# Don't resolve all repository names before the report, only do it for top repositories when needed
if command -v ghe-nwo &> /dev/null; then
    echo "Repository friendly names will be resolved for top repositories only"
else
    echo "ghe-nwo command not available - using path-based repository names"
fi

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

# Debug printing
if [[ "$DEBUG" == "true" ]]; then
    echo ""
    echo "DEBUG: First 5 lines of OVER_MAX_FILE:"
    head -5 "$OVER_MAX_FILE"
    echo ""
    echo "DEBUG: Cache size: ${#repo_name_cache[@]} repositories"
    
    # Show some examples of the repository name cache for debugging
    if [[ ${#repo_name_cache[@]} -gt 0 ]]; then
        echo "DEBUG: Sample repository name cache entries:"
        counter=0
        for repo in "${!repo_name_cache[@]}"; do
            echo "DEBUG:   $repo -> ${repo_name_cache[$repo]}"
            counter=$((counter+1))
            if [[ $counter -ge 3 ]]; then
                break
            fi
        done
    fi
fi
echo ""

# Show top repositories with large files
if (( over_max_repos > 0 )); then
    echo "TOP 5 REPOSITORIES WITH LARGEST FILES:"
    echo "------------------------------------"
    # Use a temporary file for the sorted repo counts
    top_repos_counted=$(mktemp)
    awk -F: '{print $1}' "$OVER_MAX_FILE" | sort | uniq -c | sort -nr | head -5 > "$top_repos_counted"
    
    # Create a limited cache of only the top repositories that need name resolution
    if command -v ghe-nwo &> /dev/null; then
        top_repo_path_map=()
        
        # First pass: identify full paths for top repos
        while read -r count repo_short; do
            for r in "${repos_to_analyze[@]}"; do
                this_repo_short=$(echo "$r" | sed "s|$REPO_BASE/||g" | sed 's|\.git$||g')
                this_repo_short_with_git=$(echo "$r" | sed "s|$REPO_BASE/||g")
                
                if [[ "$this_repo_short" == "$repo_short" ]] || [[ "$this_repo_short_with_git" == "$repo_short" ]]; then
                    top_repo_path_map+=("$repo_short:$r")
                    break
                fi
            done
        done < "$top_repos_counted"
        
        # Resolve names for these top repos - this limits the ghe-nwo calls to only the ones we need
        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Resolving friendly names for top repositories only"
        for mapping in "${top_repo_path_map[@]}"; do
            repo_short="${mapping%%:*}"
            repo_path="${mapping#*:}"
            
            if [[ -z "${repo_name_cache[$repo_path]}" ]]; then
                friendly_name=$(ghe-nwo "$repo_path" 2>/dev/null)
                if [[ -n "$friendly_name" ]]; then
                    repo_name_cache["$repo_path"]="$friendly_name"
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Resolved $repo_short to $friendly_name"
                fi
            fi
        done
    fi
    
    # Display the results with friendly names when available
    while read -r count repo_short; do
        display_name="$repo_short"
        
        # Find the full path for this repo
        actual_repo_path=""
        for r in "${repos_to_analyze[@]}"; do
            this_repo_short=$(echo "$r" | sed "s|$REPO_BASE/||g" | sed 's|\.git$||g')
            this_repo_short_with_git=$(echo "$r" | sed "s|$REPO_BASE/||g")
            
            if [[ "$this_repo_short" == "$repo_short" ]] || [[ "$this_repo_short_with_git" == "$repo_short" ]]; then
                actual_repo_path="$r"
                # Use cached friendly name if available
                if [[ -n "${repo_name_cache[$r]}" ]] && [[ "${repo_name_cache[$r]}" != "$repo_short" ]]; then
                    display_name="${repo_name_cache[$r]}"
                fi
                break
            fi
        done
        
        echo "  $display_name: $count large files"
    done < "$top_repos_counted"
    
    rm -f "$top_repos_counted"
    echo ""
fi

echo "REPORTS LOCATION:"
echo "---------------"
echo "* Files over ${SIZE_MAX_MB}MB: $OVER_MAX_FILE"
echo "* Files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $BETWEEN_FILE"
echo ""
echo "Analysis completed: $(date)"
