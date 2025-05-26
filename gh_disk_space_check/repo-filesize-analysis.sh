#!/bin/bash
# Save as /tmp/repo-filesize-analysis.sh
# Run with: 'sudo bash /tmp/repo-size-analysis.sh'
#
# Performance-optimized version - May 2025
# Reduces disk I/O and improves repository scanning speed

# Show help function
show_help() {
    echo "Repository File Size Analysis"
    echo "============================"
    echo "Usage: sudo bash $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help             Show this help message"
    echo "  -m, --min-size <MB>    Minimum file size to consider in MB (default: 100)"
    echo "  -M, --max-size <MB>    Maximum file size to consider in MB (default: 400)"
    echo "  -r, --resolve          Automatically resolve Git objects to filenames"
    echo "  -t, --top-objects <N>  Number of top objects to show per repository (default: 10)"
    echo "  -x, --max-repos <N>    Maximum number of repositories to process in detail (default: 50)"
    echo "  -a, --auto-adjust <y|n> Auto-adjust TOP_OBJECTS based on repository count (default: y)"
    echo "  -p, --parallel <N>     Number of parallel jobs for scanning (default: 4)"
    echo "  -P, --no-parallel      Disable parallel processing"
    echo ""
    echo "Environment Variables:"
    echo "  SIZE_MIN_MB            Same as --min-size"
    echo "  SIZE_MAX_MB            Same as --max-size"
    echo "  RESOLVE_OBJECTS        Set to 'true' to enable object resolution"
    echo "  TOP_OBJECTS            Same as --top-objects"
    echo "  MAX_REPOS              Same as --max-repos"
    echo "  AUTO_ADJUST_TOP_OBJECTS Set to 'false' to disable auto-adjustment"
    echo "  PARALLEL_JOBS          Same as --parallel"
    echo "  USE_PARALLEL           Set to 'false' to disable parallel processing"
    echo ""
    echo "Example:"
    echo "  sudo bash $0 --min-size 50 --max-size 200 --resolve --top-objects 5"
    echo "  SIZE_MIN_MB=50 SIZE_MAX_MB=200 RESOLVE_OBJECTS=true sudo bash $0"
    exit 0
}

# Parse command line arguments
# These override environment variables if specified
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -m|--min-size)
            SIZE_MIN_MB=$2
            shift 2
            ;;
        -M|--max-size)
            SIZE_MAX_MB=$2
            shift 2
            ;;
        -r|--resolve)
            RESOLVE_OBJECTS=true
            shift
            ;;
        -t|--top-objects)
            TOP_OBJECTS=$2
            shift 2
            ;;
        -x|--max-repos)
            MAX_REPOS=$2
            shift 2
            ;;
        -a|--auto-adjust)
            if [[ "$2" == "y" ]]; then
                AUTO_ADJUST_TOP_OBJECTS=true
            else
                AUTO_ADJUST_TOP_OBJECTS=false
            fi
            shift 2
            ;;
        -p|--parallel)
            PARALLEL_JOBS=$2
            shift 2
            ;;
        -P|--no-parallel)
            USE_PARALLEL=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set thresholds in MB
SIZE_MIN_MB=${SIZE_MIN_MB:-100} # Minimum file size to consider
SIZE_MAX_MB=${SIZE_MAX_MB:-400} # Maximum file size to consider
RESOLVE_OBJECTS=${RESOLVE_OBJECTS:-false} # Whether to automatically resolve large Git objects
TOP_OBJECTS=${TOP_OBJECTS:-10} # Number of top objects to show per repository when resolving
MAX_REPOS=${MAX_REPOS:-50} # Maximum number of repositories to analyze in detail
AUTO_ADJUST_TOP_OBJECTS=${AUTO_ADJUST_TOP_OBJECTS:-true} # Whether to automatically adjust TOP_OBJECTS based on repository count
PARALLEL_JOBS=${PARALLEL_JOBS:-4} # Number of parallel jobs for repository scanning
USE_PARALLEL=${USE_PARALLEL:-true} # Whether to use parallel processing
# Default values can be overridden by environment variable

# Convert MB to bytes for precise comparisons
SIZE_MAX_BYTES=$((SIZE_MAX_MB * 1024 * 1024))
SIZE_MIN_BYTES=$((SIZE_MIN_MB * 1024 * 1024))

# Initialize counters
repos_with_files_over_max=0
repos_with_files_between=0
repos_with_files_over_min=0
files_over_max=0
files_between=0

# Track repositories with specific file sizes
repos_over_max_ids=""
repos_between_ids=""

# Arrays to store repo IDs for later name resolution
declare -a repo_ids_over_max
declare -a repo_ids_between

echo "Analysis settings:"
echo "- Minimum file size: ${SIZE_MIN_MB}MB"
echo "- Maximum file size: ${SIZE_MAX_MB}MB"
echo "- Max repositories to process in detail: $MAX_REPOS"
echo "- Max objects per repository: $TOP_OBJECTS"
echo "- Automatic object resolution: $RESOLVE_OBJECTS"
echo "- Auto-adjust TOP_OBJECTS: $AUTO_ADJUST_TOP_OBJECTS"
echo "- Parallel processing: $USE_PARALLEL (jobs: $PARALLEL_JOBS)"
echo ""
echo "Analyzing repositories in /data/user/repositories..."
echo "Total repository storage: $(sudo du -hsx /data/user/repositories/)"

# Check if ghe-nwo is available
if ! command -v ghe-nwo &> /dev/null; then
    echo "WARNING: 'ghe-nwo' command not found. Repository IDs will be used instead of names."
    echo "For best results, run this script on a GitHub Enterprise server where ghe-nwo is available."
fi

# Get list of repositories
REPOS=$(sudo find /data/user/repositories -name "*.git" -type d)
TOTAL_REPOS=$(echo "$REPOS" | wc -l)

echo "Found $TOTAL_REPOS repositories to analyze"

# Create temporary files to store results
over_max_file="/tmp/repos_over_${SIZE_MAX_MB}mb.txt"
between_file="/tmp/repos_${SIZE_MIN_MB}mb_to_${SIZE_MAX_MB}mb.txt"
sudo touch ${over_max_file}.tmp ${between_file}.tmp
sudo chmod 666 ${over_max_file}.tmp ${between_file}.tmp
> ${over_max_file}.tmp
> ${between_file}.tmp

# Check for GNU Parallel
USE_PARALLEL_FINAL=$USE_PARALLEL
if [ "$USE_PARALLEL" = true ] && ! command -v parallel &>/dev/null; then
    echo "WARNING: GNU Parallel not found. Parallel processing disabled."
    echo "Install with: sudo apt-get install parallel"
    echo "On GitHub Enterprise Server, run: sudo apt-get update && sudo apt-get install -y parallel"
    USE_PARALLEL_FINAL=false
fi

# Create a function to process one repository
process_repo() {
    local REPO=$1
    local repo_count=$2
    local total_repos=$3
    local REPO_NAME=$(echo "$REPO" | sed 's|/data/user/repositories/||g' | sed 's|\.git$||g')
    
    # Determine the proper format for the repo name to appear in output once per repository
    local display_repo_name="$REPO_NAME"
    
    # If we have ghe-nwo available, try to use it for better repo name display
    if command -v ghe-nwo &> /dev/null; then
        local nwo=$(sudo ghe-nwo "$REPO" 2>/dev/null)
        if [ -n "$nwo" ]; then
            display_repo_name="$nwo"
        fi
    fi
    
    echo "[$repo_count/$total_repos] Checking $display_repo_name..."
    
    local has_file_over_max=0
    local has_file_between=0
    
    # Look for loose objects first (simpler for very small repos)
    # Run a simple find command to identify large files by size
    local large_files=$(sudo find $REPO -type f -size +${SIZE_MIN_MB}M 2>/dev/null)
    
    if [ -n "$large_files" ]; then
        # Process each large file and categorize it
        while IFS= read -r file; do
            # Skip files that don't exist anymore (could happen with concurrent operations)
            if ! sudo test -f "$file"; then
                continue
            fi
            
            # Get file size
            local file_size=$(sudo stat -c '%s' "$file" 2>/dev/null)
            if [ -z "$file_size" ]; then
                continue
            fi
            
            # Friendly display of file size
            if [ "$file_size" -ge 1073741824 ]; then
                local size_display="$(echo "scale=2; $file_size/1073741824" | bc)GB"
            elif [ "$file_size" -ge 1048576 ]; then
                local size_display="$(echo "scale=2; $file_size/1048576" | bc)MB"
            else
                local size_display="$(echo "scale=2; $file_size/1024" | bc)KB"
            fi
            
            # Categorize based on file size
            if [ "$file_size" -gt "$SIZE_MAX_BYTES" ]; then
                # Use flock to synchronize write access to the file
                flock ${over_max_file}.lock -c "echo \"$REPO:$file ($size_display)\" >> ${over_max_file}.tmp"
                has_file_over_max=1
                
            elif [ "$file_size" -gt "$SIZE_MIN_BYTES" ]; then
                # Use flock to synchronize write access to the file
                flock ${between_file}.lock -c "echo \"$REPO:$file ($size_display)\" >> ${between_file}.tmp"
                has_file_between=1
            fi
        done <<< "$large_files"
    fi
    
    # If repository had files in our categories, add it to the appropriate lists
    if [ "$has_file_over_max" -eq 1 ]; then
        # Use flock to synchronize write access to the global variables
        flock /tmp/repo_ids_over_max.lock -c "echo \"$REPO\" >> /tmp/repo_ids_over_max.list"
    fi
    
    if [ "$has_file_between" -eq 1 ]; then
        # Use flock to synchronize write access to the global variables
        flock /tmp/repo_ids_between.lock -c "echo \"$REPO\" >> /tmp/repo_ids_between.list"
    fi
}

# Process repositories
echo "Starting repository analysis..."

# Create lock files for synchronization
touch ${over_max_file}.lock ${between_file}.lock
touch /tmp/repo_ids_over_max.lock /tmp/repo_ids_between.lock
touch /tmp/repo_ids_over_max.list /tmp/repo_ids_between.list

# Process repositories in parallel or sequentially
if [ "$USE_PARALLEL_FINAL" = true ]; then
    echo "Using parallel processing with $PARALLEL_JOBS jobs..."
    
    # For one-liner scripts, we need a different approach since functions aren't exported to parallel
    # Create a temporary script with the function and execution code
    cat > /tmp/repo_processor.$$.sh << EOL
#!/bin/bash

# Copy of the process_repo function
process_repo() {
    local REPO=\$1
    local repo_count=\$2
    local total_repos=\$3
    local REPO_NAME=\$(echo "\$REPO" | sed 's|/data/user/repositories/||g' | sed 's|\.git\$||g')
    
    # Determine proper format for repo name
    local display_repo_name="\$REPO_NAME"
    
    if command -v ghe-nwo &> /dev/null; then
        local nwo=\$(sudo ghe-nwo "\$REPO" 2>/dev/null)
        if [ -n "\$nwo" ]; then
            display_repo_name="\$nwo"
        fi
    fi
    
    echo "[\$repo_count/\$total_repos] Checking \$display_repo_name..."
    
    local has_file_over_max=0
    local has_file_between=0
    
    # Look for large files
    local large_files=\$(sudo find \$REPO -type f -size +${SIZE_MIN_MB}M 2>/dev/null)
    
    if [ -n "\$large_files" ]; then
        while IFS= read -r file; do
            if ! sudo test -f "\$file"; then
                continue
            fi
            
            local file_size=\$(sudo stat -c '%s' "\$file" 2>/dev/null)
            if [ -z "\$file_size" ]; then
                continue
            fi
            
            if [ "\$file_size" -ge 1073741824 ]; then
                local size_display="\$(echo "scale=2; \$file_size/1073741824" | bc)GB"
            elif [ "\$file_size" -ge 1048576 ]; then
                local size_display="\$(echo "scale=2; \$file_size/1048576" | bc)MB"
            else
                local size_display="\$(echo "scale=2; \$file_size/1024" | bc)KB"
            fi
            
            if [ "\$file_size" -gt "$SIZE_MAX_BYTES" ]; then
                flock ${over_max_file}.lock -c "echo \"\$REPO:\$file (\$size_display)\" >> ${over_max_file}.tmp"
                has_file_over_max=1
            elif [ "\$file_size" -gt "$SIZE_MIN_BYTES" ]; then
                flock ${between_file}.lock -c "echo \"\$REPO:\$file (\$size_display)\" >> ${between_file}.tmp"
                has_file_between=1
            fi
        done <<< "\$large_files"
    fi
    
    if [ "\$has_file_over_max" -eq 1 ]; then
        flock /tmp/repo_ids_over_max.lock -c "echo \"\$REPO\" >> /tmp/repo_ids_over_max.list"
    fi
    
    if [ "\$has_file_between" -eq 1 ]; then
        flock /tmp/repo_ids_between.lock -c "echo \"\$REPO\" >> /tmp/repo_ids_between.list"
    fi
}

# Execute with passed parameters
process_repo "\$1" "\$2" "\$3"
EOL
    chmod +x /tmp/repo_processor.$$.sh
    
    # Use parallel with the temp script instead of the function directly
    echo "$REPOS" | parallel --will-cite -j "$PARALLEL_JOBS" \
        "/tmp/repo_processor.$$.sh {} {#} $TOTAL_REPOS"
    
    # Clean up
    rm -f /tmp/repo_processor.$$.sh
else
    # Process sequentially
    repo_count=0
    for REPO in $REPOS; do
        repo_count=$((repo_count + 1))
        process_repo "$REPO" "$repo_count" "$TOTAL_REPOS"
    done
fi

# Now read back the repository IDs from the temporary files
readarray -t repo_ids_over_max < /tmp/repo_ids_over_max.list
readarray -t repo_ids_between < /tmp/repo_ids_between.list

# Clean up temporary files
rm -f ${over_max_file}.lock ${between_file}.lock
rm -f /tmp/repo_ids_over_max.lock /tmp/repo_ids_between.lock
rm -f /tmp/repo_ids_over_max.list /tmp/repo_ids_between.list

# Post-processing: Convert repository IDs to names using ghe-nwo
echo "Converting repository IDs to human-readable names..."
repos_over_max=""
repos_between=""

if command -v ghe-nwo &> /dev/null; then
    # Process repositories with files over max size
    if [ ${#repo_ids_over_max[@]} -gt 0 ]; then
        echo "Processing ${#repo_ids_over_max[@]} repositories with large files..."
        for repo in "${repo_ids_over_max[@]}"; do
            repo_name=$(echo "$repo" | sed 's|/data/user/repositories/||g' | sed 's|\.git$||g')
            nwo=$(sudo ghe-nwo "$repo" 2>/dev/null)
            if [ -n "$nwo" ]; then
                repos_over_max="$repos_over_max $nwo"
                # Replace repo ID with NWO in temp file
                sudo sed -i "s|^$repo_name:|$nwo:|g" ${over_max_file}.tmp
            else
                repos_over_max="$repos_over_max $repo_name"
            fi
        done
    fi
    
    # Process repositories with files between min and max size
    if [ ${#repo_ids_between[@]} -gt 0 ]; then
        echo "Processing ${#repo_ids_between[@]} repositories with medium files..."
        for repo in "${repo_ids_between[@]}"; do
            repo_name=$(echo "$repo" | sed 's|/data/user/repositories/||g' | sed 's|\.git$||g')
            nwo=$(sudo ghe-nwo "$repo" 2>/dev/null)
            if [ -n "$nwo" ]; then
                repos_between="$repos_between $nwo"
                # Replace repo ID with NWO in temp file
                sudo sed -i "s|^$repo_name:|$nwo:|g" ${between_file}.tmp
            else
                repos_between="$repos_between $repo_name"
            fi
        done
    fi
else
    # If ghe-nwo is not available, use the IDs
    repos_over_max="$repos_over_max_ids"
    repos_between="$repos_between_ids"
fi

# Move temporary files to final files
sudo mv ${over_max_file}.tmp ${over_max_file}
sudo mv ${between_file}.tmp ${between_file}

# Print summary report
echo "======================================"
echo "REPOSITORY FILE SIZE ANALYSIS SUMMARY"
echo "======================================"
echo "Total repositories analyzed: $TOTAL_REPOS"
echo ""
echo "1. How many repos have single files in excess of ${SIZE_MAX_MB}MB?"
echo "   Answer: $repos_with_files_over_max repositories"
if [ $repos_with_files_over_max -gt 0 ]; then
    echo "   Repositories: $(echo $repos_over_max | tr ' ' ',')"
fi
echo ""
echo "2. How many repos have files between ${SIZE_MIN_MB}MB to ${SIZE_MAX_MB}MB?"
echo "   Answer: $repos_with_files_between repositories"
if [ $repos_with_files_between -gt 0 ]; then
    echo "   Repositories: $(echo $repos_between | tr ' ' ',')"
fi
echo ""
echo "3. How many repos have files larger than ${SIZE_MIN_MB}MB?"
echo "   Answer: $repos_with_files_over_min repositories"
echo ""
echo "Total files over ${SIZE_MAX_MB}MB: $files_over_max"
echo "Total files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $files_between"
echo ""
echo "Detailed report of files over ${SIZE_MAX_MB}MB: $over_max_file"
echo "Detailed report of files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $between_file"

# Optionally resolve pack objects if requested
if [ "$RESOLVE_OBJECTS" = "true" ]; then
    echo ""
    echo "Resolving Git pack objects..."

    # First, try to find the resolver script in the same directory
    SCRIPT_DIR=$(dirname "$0")
    RESOLVER_SCRIPT="${SCRIPT_DIR}/process-packs-report.sh"
    RESOLVER_SCRIPT2="${SCRIPT_DIR}/resolve-pack-objects.sh"
    
    # If not found, check if we're running from a curl pipe
    if [ ! -f "$RESOLVER_SCRIPT" ] || [ ! -x "$RESOLVER_SCRIPT" ] || [ ! -f "$RESOLVER_SCRIPT2" ]; then
        echo "Resolver scripts not found in local directory. Attempting to download from GitHub..."
        
        # Create a temporary directory
        TEMP_DIR=$(mktemp -d)
        trap 'rm -rf "$TEMP_DIR"' EXIT
        
        # Download the required scripts
        echo "Downloading process-packs-report.sh..."
        curl -s -L "https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/process-packs-report.sh" -o "${TEMP_DIR}/process-packs-report.sh"
        chmod +x "${TEMP_DIR}/process-packs-report.sh"
        
        echo "Downloading resolve-pack-objects.sh..."
        curl -s -L "https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/resolve-pack-objects.sh" -o "${TEMP_DIR}/resolve-pack-objects.sh"
        chmod +x "${TEMP_DIR}/resolve-pack-objects.sh"
        
        # Update the resolver script path
        RESOLVER_SCRIPT="${TEMP_DIR}/process-packs-report.sh"
        RESOLVER_SCRIPT2="${TEMP_DIR}/resolve-pack-objects.sh"
    fi
    
    if [ -f "$RESOLVER_SCRIPT" ] && [ -x "$RESOLVER_SCRIPT" ] && [ -f "$RESOLVER_SCRIPT2" ] && [ -x "$RESOLVER_SCRIPT2" ]; then
        echo "Starting to resolve objects in files over ${SIZE_MAX_MB}MB..."
        
        # Check if there are too many entries, and if so, process only a subset
        over_max_count=$(wc -l < "$over_max_file")
        
        # Count distinct repositories (for intelligent TOP_OBJECTS adjustment)
        distinct_repos_over=$(awk -F: '{print $1}' "$over_max_file" | sort -u | wc -l)
        
        # Dynamically adjust TOP_OBJECTS based on number of repositories and total files
        if [ "$AUTO_ADJUST_TOP_OBJECTS" = "true" ]; then
            # Calculate optimal TOP_OBJECTS value based on repository count and file count
            if [ "$distinct_repos_over" -gt 20 ]; then
                adjusted_top_objects=3  # Very large number of repositories, be very selective
            elif [ "$distinct_repos_over" -gt 10 ]; then
                adjusted_top_objects=5  # Large number of repositories
            elif [ "$distinct_repos_over" -gt 5 ]; then
                adjusted_top_objects=$((TOP_OBJECTS > 7 ? 7 : TOP_OBJECTS))  # Medium number of repositories
            else
                adjusted_top_objects=$TOP_OBJECTS  # Few repositories, use default
            fi
            
            # Further adjust based on file count - this prevents excessive processing
            if [ "$over_max_count" -gt 1000 ]; then
                adjusted_top_objects=$((adjusted_top_objects > 3 ? 3 : adjusted_top_objects))
            elif [ "$over_max_count" -gt 500 ]; then
                adjusted_top_objects=$((adjusted_top_objects > 5 ? 5 : adjusted_top_objects))
            fi
        else
            adjusted_top_objects=$((TOP_OBJECTS > 5 ? 5 : TOP_OBJECTS)) # Default to fewer objects per repo when many repos
        fi
        
        if [ "$over_max_count" -gt "$MAX_REPOS" ]; then
            echo "Large number of files ($over_max_count) in $distinct_repos_over repositories found."
            echo "Processing only the first $MAX_REPOS entries with $adjusted_top_objects objects per repo for performance."
            head -$MAX_REPOS "$over_max_file" > "${over_max_file}.subset"
            $RESOLVER_SCRIPT -f "${over_max_file}.subset" -t "$adjusted_top_objects"
            rm -f "${over_max_file}.subset"
        else
            # If few repositories, we can show more objects per repo
            if [ "$distinct_repos_over" -le 5 ]; then
                adjusted_top_objects=$TOP_OBJECTS
            fi
            echo "Processing $over_max_count entries from $distinct_repos_over repositories with $adjusted_top_objects objects per repo."
            $RESOLVER_SCRIPT -f "$over_max_file" -t "$adjusted_top_objects"
        fi
        
        echo "Starting to resolve objects in files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB..."
        between_count=$(wc -l < "$between_file")
        
        # Count distinct repositories for between file
        distinct_repos_between=$(awk -F: '{print $1}' "$between_file" | sort -u | wc -l)
        
        # Dynamically adjust TOP_OBJECTS for between-sized files
        if [ "$AUTO_ADJUST_TOP_OBJECTS" = "true" ]; then
            # Start with more restrictive limits for between-sized files
            if [ "$distinct_repos_between" -gt 20 ]; then
                adjusted_top_objects=2  # Very large number of repositories, be extremely selective
            elif [ "$distinct_repos_between" -gt 10 ]; then
                adjusted_top_objects=3  # Large number of repositories
            elif [ "$distinct_repos_between" -gt 5 ]; then
                adjusted_top_objects=$((TOP_OBJECTS > 5 ? 5 : TOP_OBJECTS))  # Medium number of repositories
            else
                adjusted_top_objects=$((TOP_OBJECTS > 7 ? 7 : TOP_OBJECTS))  # Few repositories, can be more generous
            fi
            
            # Further adjust based on file count
            if [ "$between_count" -gt 1000 ]; then
                adjusted_top_objects=$((adjusted_top_objects > 2 ? 2 : adjusted_top_objects))
            elif [ "$between_count" -gt 500 ]; then
                adjusted_top_objects=$((adjusted_top_objects > 3 ? 3 : adjusted_top_objects))
            fi
        else
            adjusted_top_objects=$((TOP_OBJECTS > 3 ? 3 : TOP_OBJECTS)) # Even fewer objects for the between category
        fi
        
        if [ "$between_count" -gt "$MAX_REPOS" ]; then
            echo "Large number of files ($between_count) in $distinct_repos_between repositories found."
            echo "Processing only the first $MAX_REPOS entries with $adjusted_top_objects objects per repo for performance."
            head -$MAX_REPOS "$between_file" > "${between_file}.subset"
            $RESOLVER_SCRIPT -f "${between_file}.subset" -t "$adjusted_top_objects"
            rm -f "${between_file}.subset"
        else
            # If few repositories, we can show more objects per repo
            if [ "$distinct_repos_between" -le 5 ]; then
                adjusted_top_objects=$TOP_OBJECTS
            fi
            echo "Processing $between_count entries from $distinct_repos_between repositories with $adjusted_top_objects objects per repo."
            $RESOLVER_SCRIPT -f "$between_file" -t "$adjusted_top_objects"
        fi
        
        echo ""
        echo "Resolved object reports:"
        echo "Files over ${SIZE_MAX_MB}MB: ${over_max_file}_resolved.txt"
        echo "Files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: ${between_file}_resolved.txt"
    else
        echo "Warning: Failed to find or download resolver scripts"
        echo "To manually resolve Git objects, run these commands:"
        echo "  curl -s -L https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/process-packs-report.sh -o ~/process-packs-report.sh"
        echo "  curl -s -L https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/resolve-pack-objects.sh -o ~/resolve-pack-objects.sh"
        echo "  chmod +x ~/process-packs-report.sh ~/resolve-pack-objects.sh"
        echo "  ~/process-packs-report.sh -f $over_max_file"
        echo "  ~/process-packs-report.sh -f $between_file"
    fi
fi
