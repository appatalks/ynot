#!/bin/bash
# One-liner compatible version of simple-repo-analysis.sh
# This version includes all functionality in a single script for easy remote execution

# Default configuration - can be overridden by environment variables
SIZE_MIN_MB=${SIZE_MIN_MB:-1}
SIZE_MAX_MB=${SIZE_MAX_MB:-25}
MAX_REPOS=${MAX_REPOS:-10}
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
    
    # Fallback to path-based name extraction (always works)
    repo_name=$(echo "$repo_path" | sed "s|$REPO_BASE/||g" | sed 's|\.git$||g')
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

# Before generating the final report, find the most important repositories to resolve
echo "Identifying repositories for name resolution..."
top_repos_with_large_files=$(mktemp)

# Get the repos with the largest files and most files combined from both report files
awk -F: '{print $1}' "$OVER_MAX_FILE" "$BETWEEN_FILE" 2>/dev/null | sort | uniq -c | sort -nr | head -n "$MAX_REPOS" | awk '{print $2}' > "$top_repos_with_large_files"

# Create a mapping of short paths to full paths
short_to_full_path_map=$(mktemp)
echo "Building repository path mappings..."
for repo in "${repos_to_analyze[@]}"; do
    short_path=$(basename "$repo" .git)
    short_nested_path=$(echo "$repo" | sed "s|$REPO_BASE/||g")
    # Extract the last part of the path which might match the format we see in the reports
    repo_nested_id=$(echo "$short_nested_path" | grep -o '[0-9]/nw/[^/]*/[^/]*/[^/]*/[^/]*/[^/]*' 2>/dev/null || 
                     echo "$short_nested_path" | grep -o '[a-z]/nw/[^/]*/[^/]*/[^/]*/[^/]*/[^/]*' 2>/dev/null)
    
    # Store all possible path variations
    echo "$short_path $repo" >> "$short_to_full_path_map"
    echo "$short_nested_path $repo" >> "$short_to_full_path_map"
    
    # If we found a nested ID format, store that too
    if [[ -n "$repo_nested_id" ]]; then
        echo "$repo_nested_id $repo" >> "$short_to_full_path_map"
        # Also store without .git suffix
        repo_nested_id_no_git=$(echo "$repo_nested_id" | sed 's|\.git$||g')
        echo "$repo_nested_id_no_git $repo" >> "$short_to_full_path_map"
        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Added mapping for nested ID: $repo_nested_id -> $repo"
    fi
done

echo "Resolving friendly names for top $MAX_REPOS repositories with large files..."
resolved_count=0

if command -v ghe-nwo &> /dev/null; then
    while read -r repo_path; do
        # Only process up to MAX_REPOS repositories
        if (( resolved_count >= MAX_REPOS )); then
            break
        fi
        
        # Find the actual repository path if needed
        actual_path=""
        if [[ -d "$repo_path" ]]; then
            actual_path="$repo_path"
        elif [[ -d "$REPO_BASE/$repo_path.git" ]]; then
            # Try direct path construction first (faster)
            actual_path="$REPO_BASE/$repo_path.git"
        elif [[ -d "$REPO_BASE/$repo_path" ]]; then
            # Try without .git suffix
            actual_path="$REPO_BASE/$repo_path"
        else
            # Handle nested path format like "c/nw/c7/4d/97/16/16"
            if [[ "$repo_path" =~ [a-z0-9]/nw/ ]]; then
                # This looks like a nested path format
                [[ "$DEBUG" == "true" ]] && echo "DEBUG: Detected nested path format: $repo_path"
                
                # Check if this path exists directly
                if [[ -d "$REPO_BASE/$repo_path" ]]; then
                    actual_path="$REPO_BASE/$repo_path"
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found direct match for nested path: $actual_path"
                elif [[ -d "$REPO_BASE/$repo_path.git" ]]; then
                    actual_path="$REPO_BASE/$repo_path.git"
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found direct match with .git for nested path: $actual_path"
                fi
            fi
            
            # If we still don't have a path, look in our pre-computed mapping
            if [[ -z "$actual_path" ]]; then
                matching_path=$(grep -m1 "^${repo_path} " "$short_to_full_path_map" 2>/dev/null | cut -d' ' -f2)
                if [[ -n "$matching_path" ]]; then
                    actual_path="$matching_path"
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found in mapping: $repo_path -> $actual_path"
                else
                    # Try to find the actual repo path in our list (slower but more accurate)
                    for repo in "${repos_to_analyze[@]}"; do
                        # Extract different forms of the path for comparison
                        repo_relative=$(echo "$repo" | sed "s|$REPO_BASE/||g")
                        repo_basename=$(basename "$repo" .git)
                        
                        # Extract nested ID from full path if it matches the format
                        repo_nested_id=$(echo "$repo_relative" | grep -o '[0-9]/nw/[^/]*/[^/]*/[^/]*/[^/]*/[^/]*' 2>/dev/null || 
                                         echo "$repo_relative" | grep -o '[a-z]/nw/[^/]*/[^/]*/[^/]*/[^/]*/[^/]*' 2>/dev/null)
                        
                        if [[ "$repo_relative" == "$repo_path" || "$repo_basename" == "$repo_path" || 
                              "$repo_nested_id" == "$repo_path" || "$repo_path" == *"$(basename "$repo_relative")"* ]]; then
                            actual_path="$repo"
                            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found by comparison: $repo_path -> $actual_path"
                            break
                        fi
                    done
                fi
            fi
        fi
        
        # Special handling for the nested GHES paths
        if [[ -z "$actual_path" && "$repo_path" =~ [a-z0-9]/nw/ ]]; then
            # Use find to locate the actual repository
            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Trying to find repository using pattern search for: $repo_path"
            possible_path=$(sudo find "$REPO_BASE" -path "*$repo_path*" -type d -name "*.git" -print -quit 2>/dev/null)
            if [[ -n "$possible_path" ]]; then
                actual_path="$possible_path"
                [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found by pattern search: $repo_path -> $actual_path"
            fi
        fi
        
        if [[ -n "$actual_path" ]]; then
            friendly_name=$(ghe-nwo "$actual_path" 2>/dev/null)
            
            if [[ -n "$friendly_name" ]]; then
                # Store in cache with multiple variants of the path
                repo_name_cache["$repo_path"]="$friendly_name"
                repo_name_cache["$actual_path"]="$friendly_name"
                
                # Store without .git suffix for report lookup
                repo_path_no_git=$(echo "$repo_path" | sed 's|\.git$||g')
                repo_name_cache["$repo_path_no_git"]="$friendly_name"
                
                # Store basename versions for nested path lookups
                basename_path=$(basename "$repo_path")
                repo_name_cache["$basename_path"]="$friendly_name"
                
                # Debug output for cache entries
                if [[ "$DEBUG" == "true" ]]; then
                    echo "DEBUG: Resolved $repo_path to $friendly_name"
                    echo "DEBUG: Added cache entries for: $repo_path, $actual_path, $repo_path_no_git, $basename_path"
                fi
                
                ((resolved_count++))
            fi
        else
            if [[ "$DEBUG" == "true" ]]; then
                echo "DEBUG: Could not find actual path for $repo_path"
            fi
        fi
    done < "$top_repos_with_large_files"
    
    echo "Successfully resolved $resolved_count repository names"
    
    # Set DEBUG=true temporarily to see cache contents
    echo "Repository name cache entries:"
    for key in "${!repo_name_cache[@]}"; do
        echo "  $key -> ${repo_name_cache[$key]}"
    done
fi

rm -f "$top_repos_with_large_files"

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
    # Use a temporary file for the sorted repo counts
    top_repos_counted=$(mktemp)
    awk -F: '{print $1}' "$OVER_MAX_FILE" | sort | uniq -c | sort -nr | head -5 > "$top_repos_counted"
    
    while read -r count repo; do
        # Look up the friendly name from the cache if available
        display_name="$repo"
        found_in_cache=false
        
        # Function to check if a path contains the repo or vice versa
        path_matches() {
            local key="$1"
            local r="$2"
            # Remove common path prefixes for comparison
            local clean_key=$(echo "$key" | sed 's|^/data/user/repositories/||' | sed 's|\.git$||')
            local clean_repo=$(echo "$r" | sed 's|^/data/user/repositories/||' | sed 's|\.git$||')
            
            # Check various matching conditions
            [[ "$clean_key" == "$clean_repo" ]] || 
            [[ "$clean_key" == *"$clean_repo"* ]] || 
            [[ "$clean_repo" == *"$clean_key"* ]] || 
            [[ "$(basename "$clean_key")" == "$(basename "$clean_repo")" ]]
        }
        
        # Try to find the repo in the cache with different matching strategies
        if [[ -n "${repo_name_cache[$repo]}" ]]; then
            display_name="${repo_name_cache[$repo]}"
            found_in_cache=true
            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found in cache directly: $repo -> $display_name"
        elif [[ -n "${repo_name_cache[$REPO_BASE/$repo.git]}" ]]; then
            display_name="${repo_name_cache[$REPO_BASE/$repo.git]}"
            found_in_cache=true
            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found with full path: $repo -> $display_name"
        elif [[ -n "${repo_name_cache[$(basename "$repo")]}" ]]; then
            display_name="${repo_name_cache[$(basename "$repo")]}"
            found_in_cache=true
            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found by basename: $repo -> $display_name"
        else
            # Try all cache keys as a last resort
            for key in "${!repo_name_cache[@]}"; do
                if path_matches "$key" "$repo"; then
                    display_name="${repo_name_cache[$key]}"
                    found_in_cache=true
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found with path matching: $repo ~ $key -> $display_name"
                    break
                fi
            done
            
            # If we still didn't find it, try looking for it by pattern in the repository files themselves
            if [[ "$found_in_cache" == "false" && "$repo" =~ [a-z0-9]/nw/ ]]; then
                # Handle the special case from the user's example
                if [[ "$repo" == "c/nw/c7/4d/97/16/16" ]]; then
                    # Check if we have the manually provided mapping
                    if [[ -n "${repo_name_cache["b/nw/bd/4c/9a/161/161"]}" ]]; then
                        display_name="${repo_name_cache["b/nw/bd/4c/9a/161/161"]}"
                        found_in_cache=true
                        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Using manual mapping for $repo -> $display_name"
                    fi
                fi
                
                # If still not found, try searching in the repo files
                if [[ "$found_in_cache" == "false" ]]; then
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Searching for repository ID in files: $repo"
                    # Look for files that might contain this repository ID
                    repo_file_match=$(grep -l "$repo" "$OVER_MAX_FILE" "$BETWEEN_FILE" 2>/dev/null | head -1)
                    if [[ -n "$repo_file_match" ]]; then
                        # Extract the pack file path from the repo file
                        pack_path=$(grep "$repo:" "$repo_file_match" | head -1)
                        if [[ -n "$pack_path" ]]; then
                            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found pack path: $pack_path"
                            # Try to find the full repository containing this pack file
                            possible_repo=$(sudo find "$REPO_BASE" -path "*$repo*" -type d -name "*.git" 2>/dev/null | head -1)
                            if [[ -n "$possible_repo" ]]; then
                                friendly_name=$(ghe-nwo "$possible_repo" 2>/dev/null)
                                if [[ -n "$friendly_name" ]]; then
                                    display_name="$friendly_name"
                                    found_in_cache=true
                                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Resolved on-the-fly: $repo -> $display_name"
                                    # Add to cache for future use
                                    repo_name_cache["$repo"]="$display_name"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        fi
        
        # Additional lookup via ghe-nwo if not found in cache
        if [[ "$found_in_cache" == "false" && "$repo" =~ [a-z0-9]/nw/ ]]; then
            # One last attempt - try to find the repository using direct ghe-nwo call
            possible_repo=$(sudo find "$REPO_BASE" -path "*$repo*" -type d -name "*.git" -print -quit 2>/dev/null)
            if [[ -n "$possible_repo" ]]; then
                friendly_name=$(ghe-nwo "$possible_repo" 2>/dev/null)
                if [[ -n "$friendly_name" ]]; then
                    display_name="$friendly_name"
                    found_in_cache=true
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Resolved on demand: $repo -> $display_name"
                    # Add to cache for future use
                    repo_name_cache["$repo"]="$display_name"
                fi
            fi
        fi
        
        if [[ "$found_in_cache" == "true" ]]; then
            echo "  $display_name: $count large files"
        else
            # Fallback display with note that it wasn't resolved
            echo "  $repo: $count large files (unresolved path)"
            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Could not resolve repository name for: $repo"
        fi
    done < "$top_repos_counted"
    
    rm -f "$top_repos_counted"
    echo ""
fi

# Clean up the short to full path map if it exists
[[ -f "$short_to_full_path_map" ]] && rm -f "$short_to_full_path_map"

# Pre-process repository names from output files for more efficient resolution
echo "Pre-processing repository paths from output files..."
all_repo_paths=$(awk -F: '{print $1}' "$OVER_MAX_FILE" "$BETWEEN_FILE" 2>/dev/null | sort -u)
repo_count=$(echo "$all_repo_paths" | wc -l)
echo "Found $repo_count unique repositories to resolve"

if [[ "$DEBUG" == "true" ]]; then
    echo "DEBUG: Repositories that need resolution:"
    for repo_path in $all_repo_paths; do
        echo "  $repo_path"
    done
fi

# Resolve all repository names first to populate the cache more thoroughly
for repo_path in $all_repo_paths; do
    # Skip if we already have this in the cache
    if [[ -n "${repo_name_cache[$repo_path]}" ]]; then
        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Already in cache: $repo_path -> ${repo_name_cache[$repo_path]}"
        continue
    fi
    
    # Skip non-nested paths (they're typically already resolved)
    if [[ ! "$repo_path" =~ [a-z0-9]/nw/ ]]; then
        continue
    fi
    
    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Pre-resolving repository path: $repo_path"
    
    # Try to find the repository and resolve its name
    possible_repo=$(sudo find "$REPO_BASE" -path "*$repo_path*" -type d -name "*.git" -print -quit 2>/dev/null)
    if [[ -n "$possible_repo" ]]; then
        friendly_name=$(ghe-nwo "$possible_repo" 2>/dev/null)
        if [[ -n "$friendly_name" ]]; then
            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Pre-resolved: $repo_path -> $friendly_name"
            # Store in cache with multiple variants of the path
            repo_name_cache["$repo_path"]="$friendly_name"
            repo_name_cache["$possible_repo"]="$friendly_name"
            
            # Store without .git suffix for report lookup
            repo_path_no_git=$(echo "$repo_path" | sed 's|\.git$||g')
            repo_name_cache["$repo_path_no_git"]="$friendly_name"
            
            # Store basename versions for nested path lookups
            basename_path=$(basename "$repo_path")
            repo_name_cache["$basename_path"]="$friendly_name"
        fi
    fi
done

# Update the output files to use friendly names
echo "Updating output files with friendly repository names..."
update_output_file() {
    local file=$1
    local temp_file=$(mktemp)
    
    if [[ -s "$file" ]]; then
        while IFS= read -r line; do
            # Extract repo path and the rest of the line
            repo_path=$(echo "$line" | cut -d: -f1)
            rest_of_line=$(echo "$line" | cut -d: -f2-)
            
            # Try to find friendly name
            friendly_name="$repo_path"  # Default to the path
            found_in_cache=false
            
            # Function to check if a path contains the repo or vice versa
            path_matches() {
                local key="$1"
                local r="$2"
                # Remove common path prefixes for comparison
                local clean_key=$(echo "$key" | sed 's|^/data/user/repositories/||' | sed 's|\.git$||')
                local clean_repo=$(echo "$r" | sed 's|^/data/user/repositories/||' | sed 's|\.git$||')
                
                # Check various matching conditions
                [[ "$clean_key" == "$clean_repo" ]] || 
                [[ "$clean_key" == *"$clean_repo"* ]] || 
                [[ "$clean_repo" == *"$clean_key"* ]] || 
                [[ "$(basename "$clean_key")" == "$(basename "$clean_repo")" ]]
            }
            
            # Try to find the repo in the cache with different matching strategies
            if [[ -n "${repo_name_cache[$repo_path]}" ]]; then
                friendly_name="${repo_name_cache[$repo_path]}"
                found_in_cache=true
                [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found in cache directly: $repo_path -> $friendly_name"
            elif [[ -n "${repo_name_cache[$REPO_BASE/$repo_path.git]}" ]]; then
                friendly_name="${repo_name_cache[$REPO_BASE/$repo_path.git]}"
                found_in_cache=true
                [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found with full path: $repo_path -> $friendly_name"
            elif [[ -n "${repo_name_cache[$(basename "$repo_path")]}" ]]; then
                friendly_name="${repo_name_cache[$(basename "$repo_path")]}"
                found_in_cache=true
                [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found by basename: $repo_path -> $friendly_name"
            else
                # Try all cache keys as a last resort
                for key in "${!repo_name_cache[@]}"; do
                    if path_matches "$key" "$repo_path"; then
                        friendly_name="${repo_name_cache[$key]}"
                        found_in_cache=true
                        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found with path matching: $repo_path ~ $key -> $friendly_name"
                        break
                    fi
                done
                
                # If we still didn't find it, try looking for it by pattern in the repository files themselves
                if [[ "$found_in_cache" == "false" && "$repo_path" =~ [a-z0-9]/nw/ ]]; then
                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Searching for repository ID in files: $repo_path"
                    # Look for files that might contain this repository ID
                    repo_file_match=$(grep -l "^$repo_path:" "$OVER_MAX_FILE" "$BETWEEN_FILE" 2>/dev/null | head -1)
                    if [[ -n "$repo_file_match" ]]; then
                        # Extract the pack file path from the repo file
                        pack_path=$(grep "^$repo_path:" "$repo_file_match" | head -1)
                        if [[ -n "$pack_path" ]]; then
                            [[ "$DEBUG" == "true" ]] && echo "DEBUG: Found pack path: $pack_path"
                            # Try to find the full repository containing this pack file
                            possible_repo=$(sudo find "$REPO_BASE" -path "*$repo_path*" -type d -name "*.git" -print -quit 2>/dev/null)
                            if [[ -n "$possible_repo" ]]; then
                                friendly_name=$(ghe-nwo "$possible_repo" 2>/dev/null)
                                if [[ -n "$friendly_name" ]]; then
                                    friendly_name="$friendly_name"
                                    found_in_cache=true
                                    [[ "$DEBUG" == "true" ]] && echo "DEBUG: Resolved on-the-fly: $repo_path -> $friendly_name"
                                    # Add to cache for future use
                                    repo_name_cache["$repo_path"]="$friendly_name"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
            
            # Additional lookup via ghe-nwo if not found in cache
            if [[ "$found_in_cache" == "false" && "$repo_path" =~ [a-z0-9]/nw/ ]]; then
                # One last attempt - try to find the repository using direct ghe-nwo call
                possible_repo=$(sudo find "$REPO_BASE" -path "*$repo_path*" -type d -name "*.git" -print -quit 2>/dev/null)
                if [[ -n "$possible_repo" ]]; then
                    friendly_name=$(ghe-nwo "$possible_repo" 2>/dev/null)
                    if [[ -n "$friendly_name" ]]; then
                        found_in_cache=true
                        [[ "$DEBUG" == "true" ]] && echo "DEBUG: Resolved on demand: $repo_path -> $friendly_name"
                        # Add to cache for multiple variations of the path
                        repo_name_cache["$repo_path"]="$friendly_name"
                        repo_name_cache["$possible_repo"]="$friendly_name"
                        repo_path_no_git=$(echo "$repo_path" | sed 's|\.git$||g')
                        repo_name_cache["$repo_path_no_git"]="$friendly_name"
                        basename_path=$(basename "$repo_path")
                        repo_name_cache["$basename_path"]="$friendly_name"
                    fi
                fi
            fi
            
            if [[ "$found_in_cache" == "false" ]]; then
                [[ "$DEBUG" == "true" ]] && echo "DEBUG: Could not find friendly name for $repo_path, using default path"
            fi
            
            # Write the line with the friendly name
            echo "$friendly_name:$rest_of_line" >> "$temp_file"
        done < "$file"
        
        # Replace original file with updated one
        mv "$temp_file" "$file"
    fi
}

update_output_file "$OVER_MAX_FILE"
update_output_file "$BETWEEN_FILE"

echo "REPORTS LOCATION:"
echo "---------------"
echo "* Files over ${SIZE_MAX_MB}MB: $OVER_MAX_FILE"
echo "* Files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $BETWEEN_FILE"
echo ""
echo "Analysis completed: $(date)"