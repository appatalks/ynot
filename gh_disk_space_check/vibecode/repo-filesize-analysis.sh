#!/bin/bash

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
    echo "  -T, --timeout <sec>    Timeout in seconds for find commands (default: 60)"
    echo "  -d, --include-deleted  Include repositories that appear to be deleted but not purged"
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
    echo "  FIND_TIMEOUT           Same as --timeout"
    echo "  INCLUDE_DELETED        Set to 'true' to include deleted repositories"
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
        -T|--timeout)
            FIND_TIMEOUT=$2
            shift 2
            ;;
        -d|--include-deleted)
            INCLUDE_DELETED=true
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
FIND_TIMEOUT=${FIND_TIMEOUT:-60} # Timeout in seconds for find commands
INCLUDE_DELETED=${INCLUDE_DELETED:-false} # Whether to include repositories that appear to be deleted
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

echo "====================================="
echo "GITHUB REPOSITORY SIZE ANALYZER"
echo "====================================="
echo "Analysis started: $(date)"
echo "This tool scans repositories to identify large files that may be consuming"
echo "significant disk space. It first performs a quick scan to identify the top"
echo "repositories by size, then looks for specific large files within them."
echo ""
echo "ANALYSIS SETTINGS:"
echo "- Minimum file size: ${SIZE_MIN_MB}MB"
echo "- Maximum file size: ${SIZE_MAX_MB}MB"
echo "- Max repositories to analyze in detail: $MAX_REPOS"
echo "- Max objects per repository: $TOP_OBJECTS"
echo "- Include deleted repositories: $INCLUDE_DELETED"
echo "- Automatic object resolution: $RESOLVE_OBJECTS"
echo "- Parallel processing: $USE_PARALLEL (jobs: $PARALLEL_JOBS)"
echo "- Find command timeout: ${FIND_TIMEOUT}s"
echo ""
echo "Analyzing repositories in /data/user/repositories..."
echo "Initial estimate: $(sudo du -hsx /data/user/repositories/ 2>/dev/null || echo "Unknown")"

# Check if ghe-nwo is available
if ! command -v ghe-nwo &> /dev/null; then
    echo "WARNING: 'ghe-nwo' command not found. Repository IDs will be used instead of names."
    echo "For best results, run this script on a GitHub Enterprise server where ghe-nwo is available."
fi

# Identify repositories and check validity
echo "Scanning for repositories..."
REPOS=$(sudo find /data/user/repositories -name "*.git" -type d)
INITIAL_REPOS_COUNT=$(echo "$REPOS" | wc -l)
echo "Found $INITIAL_REPOS_COUNT Git repositories"

# Create a temporary file to store repositories for analysis
ACTIVE_REPOS_FILE="/tmp/active_repos_$$"
> "$ACTIVE_REPOS_FILE"

if [ "$INCLUDE_DELETED" = "false" ]; then
    # Filter out repositories that seem deleted but not purged
    echo "Filtering out deleted/empty repositories..."
    for REPO in $REPOS; do
        # Check if repository has objects directory with pack files - simple heuristic for active repos
        if sudo test -d "$REPO/objects" && sudo find "$REPO" -type f -name "*.pack" | grep -q .; then
            echo "$REPO" >> "$ACTIVE_REPOS_FILE"
        fi
    done
    
    # Read filtered repositories
    REPOS=$(cat "$ACTIVE_REPOS_FILE")
    TOTAL_REPOS=$(echo "$REPOS" | wc -l)
    echo "Found $TOTAL_REPOS active repositories after filtering"
    echo "Excluded $(($INITIAL_REPOS_COUNT - $TOTAL_REPOS)) repositories that appear to be deleted/empty"
else
    # No filtering, use all repositories
    echo "$REPOS" > "$ACTIVE_REPOS_FILE"
    TOTAL_REPOS=$INITIAL_REPOS_COUNT
    echo "Including all repositories, including potentially deleted ones"
fi

# Now do a quick size scan to identify the largest repositories
echo "Performing initial size scan to identify largest repositories..."
ALL_REPOS_SIZES_FILE="/tmp/all_repos_sizes_$$"
TOP_REPOS_FILE="/tmp/top_repos_$$"

# Get size of all repositories with faster parallelized approach
if [ "$USE_PARALLEL_FINAL" = true ] && command -v parallel &>/dev/null; then
    echo "$REPOS" | parallel --will-cite -j "$PARALLEL_JOBS" "sudo du -s {} 2>/dev/null" > "$ALL_REPOS_SIZES_FILE"
else
    sudo du -s $REPOS 2>/dev/null > "$ALL_REPOS_SIZES_FILE"
fi

# Calculate total size of all repos for context
TOTAL_SIZE_KB=$(awk '{sum+=$1} END {print sum}' "$ALL_REPOS_SIZES_FILE")
TOTAL_SIZE_MB=$((TOTAL_SIZE_KB / 1024))
TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE_MB/1024" | bc)

# Initialize USE_PARALLEL_FINAL variable early to avoid potential issues
USE_PARALLEL_FINAL=$USE_PARALLEL

# Find a sensible threshold - either top N repos or repos above certain size
if [ $TOTAL_REPOS -gt $((MAX_REPOS * 10)) ]; then
    # With many repos, focus on largest ones
    sort -rn "$ALL_REPOS_SIZES_FILE" | head -n $MAX_REPOS > "$TOP_REPOS_FILE"
    SELECTION_METHOD="Top $MAX_REPOS repositories by size"
else
    # With fewer repos, include all larger than 1% of total size
    SIZE_THRESHOLD=$((TOTAL_SIZE_KB / 100))
    if [ $SIZE_THRESHOLD -lt 1024 ]; then  # At least 1MB
        SIZE_THRESHOLD=1024
    fi
    sort -rn "$ALL_REPOS_SIZES_FILE" | awk -v threshold="$SIZE_THRESHOLD" '$1 >= threshold' > "$TOP_REPOS_FILE"
    REPOS_ABOVE_THRESHOLD=$(wc -l < "$TOP_REPOS_FILE")
    
    # If we got too many repos, cap it at MAX_REPOS
    if [ $REPOS_ABOVE_THRESHOLD -gt $MAX_REPOS ]; then
        sort -rn "$ALL_REPOS_SIZES_FILE" | head -n $MAX_REPOS > "$TOP_REPOS_FILE"
        SELECTION_METHOD="Top $MAX_REPOS repositories by size"
    else 
        SELECTION_METHOD="$REPOS_ABOVE_THRESHOLD repositories larger than $SIZE_THRESHOLD KB"
    fi
fi

TOP_REPOS_COUNT=$(wc -l < "$TOP_REPOS_FILE")
TOP_REPOS_SIZE_KB=$(awk '{sum+=$1} END {print sum}' "$TOP_REPOS_FILE")
TOP_REPOS_SIZE_PERCENT=$(echo "scale=1; 100 * $TOP_REPOS_SIZE_KB / $TOTAL_SIZE_KB" | bc)

echo "Total repository storage: $TOTAL_SIZE_GB GB across $TOTAL_REPOS repositories"
echo "Selected $SELECTION_METHOD for detailed analysis"
echo "These repositories account for $TOP_REPOS_SIZE_PERCENT% of total storage"

# Create temporary files to store results
over_max_file="/tmp/repos_over_${SIZE_MAX_MB}mb.txt"
between_file="/tmp/repos_${SIZE_MIN_MB}mb_to_${SIZE_MAX_MB}mb.txt"
sudo touch ${over_max_file}.tmp ${between_file}.tmp
sudo chmod 666 ${over_max_file}.tmp ${between_file}.tmp
> ${over_max_file}.tmp
> ${between_file}.tmp

# Check for GNU Parallel
USE_PARALLEL_FINAL=$USE_PARALLEL
if [ "$USE_PARALLEL" = true ]; then
    if ! command -v parallel &>/dev/null; then
        USE_PARALLEL_FINAL=false
    else
        # Make sure parallel version is compatible
        parallel --no-notice --version >/dev/null 2>&1 || {
            echo "WARNING: Your version of GNU Parallel may have issues. Disabling parallel processing."
            USE_PARALLEL_FINAL=false
        }
    fi
fi

# Create a function to process one repository
process_repo() {
    local REPO=$1
    local repo_count=$2
    local total_repos=$3
    local REPO_NAME=$(extract_repo_name "$REPO")
    
    # Determine the proper format for the repo name to appear in output once per repository
    local display_repo_name="$REPO_NAME"
    
    # If we have ghe-nwo available, try to use it for better repo name display
    if command -v ghe-nwo &> /dev/null; then
        local nwo=$(sudo ghe-nwo "$REPO" 2>/dev/null)
        if [ -n "$nwo" ]; then
            display_repo_name="$nwo"
            # Also store in a temp lookup file for later use
            echo "$REPO:$nwo" >> /tmp/repo_nwo_lookup.$$
        else
            # No NWO available, use a cleaned up path
            echo "$REPO:$REPO_NAME" >> /tmp/repo_nwo_lookup.$$
        fi
    fi
    
    echo "[$repo_count/$total_repos] Checking $display_repo_name..."
    
    local has_file_over_max=0
    local has_file_between=0
    
    # First check pack files which are likely to be large
    local pack_dir="$REPO/objects/pack"
    if sudo test -d "$pack_dir"; then
        # Get list of large pack files first - they're most likely to contain large objects
        # Use timeout to prevent hanging on problematic repositories
        local large_packs=$(timeout $FIND_TIMEOUT sudo find "$pack_dir" -name "*.pack" -size +${SIZE_MIN_MB}M 2>/dev/null)
        
        if [ -n "$large_packs" ]; then
            # Process each pack file
            while IFS= read -r pack_file; do
                # Get file size
                local file_size=$(sudo stat -c '%s' "$pack_file" 2>/dev/null)
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
                    flock ${over_max_file}.lock -c "echo \"$REPO:$pack_file ($size_display)\" >> ${over_max_file}.tmp"
                    has_file_over_max=1
                elif [ "$file_size" -gt "$SIZE_MIN_BYTES" ]; then
                    flock ${between_file}.lock -c "echo \"$REPO:$pack_file ($size_display)\" >> ${between_file}.tmp"
                    has_file_between=1
                fi
            done <<< "$large_packs"
        fi
    fi
    
    # Now look for other large files (more expensive operation, but needed for completeness)
    # Skip objects/pack since we already processed those, and use timeout to avoid hanging
    local large_files=$(timeout $FIND_TIMEOUT sudo find $REPO -path "$REPO/objects/pack" -prune -o -type f -size +${SIZE_MIN_MB}M -print 2>/dev/null)
    
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

# Function to extract repository name from path, handling special formats like /nw/ paths
extract_repo_name() {
    local repo_path="$1"
    local repo_name=""
    
    # Handle standard repository path format
    if [[ "$repo_path" == "/data/user/repositories/"* ]]; then
        repo_name=$(echo "$repo_path" | sed 's|/data/user/repositories/||g' | sed 's|\.git$||g')
        
        # Special handling for compressed repository paths with /nw/ format
        # Example: /data/user/repositories/a/nw/a8/7f/f6/4/4.git
        if [[ "$repo_name" == *"/nw/"* ]]; then
            # Keep the compressed format as is - it's a special case for GitHub Enterprise Server
            # Format correctly for display - but don't remove the /nw/ part
            repo_name=$(echo "$repo_name" | sed 's|/nw/|/nw/|g') # Preserve the /nw/ part
            
            # Additional debugging if needed
            if [ "$VERBOSE" = true ]; then
                echo "Compressed path detected: $repo_path -> $repo_name" >&2
            fi
        fi
    else
        # If not a standard path, return as is
        repo_name="$repo_path"
    fi
    
    # Return the extracted name
    echo "$repo_name"
}

# Process repositories
echo "Starting repository analysis..."

# Create lock files for synchronization
touch ${over_max_file}.lock ${between_file}.lock
touch /tmp/repo_ids_over_max.lock /tmp/repo_ids_between.lock
touch /tmp/repo_ids_over_max.list /tmp/repo_ids_between.list

# Extract just the repository paths from the top repos file
REPOS_TO_PROCESS=$(awk '{print $2}' "$TOP_REPOS_FILE")

# Process repositories in parallel or sequentially
if [ "$USE_PARALLEL_FINAL" = true ]; then
    echo "Using parallel processing with $PARALLEL_JOBS jobs on top $TOP_REPOS_COUNT repositories..."
    
    # For one-liner scripts, we need a different approach since functions aren't exported to parallel
    # Create a temporary script that's completely standalone with all variables needed
    cat > /tmp/repo_processor.$$.sh << EOL
#!/bin/bash

# Export all necessary variables that were passed into the main script
SIZE_MIN_MB=${SIZE_MIN_MB}
SIZE_MAX_MB=${SIZE_MAX_MB}
SIZE_MIN_BYTES=${SIZE_MIN_BYTES}
SIZE_MAX_BYTES=${SIZE_MAX_BYTES}
over_max_file="${over_max_file}"
between_file="${between_file}"
FIND_TIMEOUT=${FIND_TIMEOUT}

# Standalone version of process_repo function
process_one_repo() {
    local REPO="\$1"
    local repo_count="\$2"
    local total_repos="\$3"
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
    
    # First check pack files which are likely to be large
    local pack_dir="\$REPO/objects/pack"
    if sudo test -d "\$pack_dir"; then
        # Get list of large pack files first, with timeout
        local large_packs=\$(timeout \${FIND_TIMEOUT:-60} sudo find "\$pack_dir" -name "*.pack" -size +\${SIZE_MIN_MB}M 2>/dev/null)
        
        if [ -n "\$large_packs" ]; then
            while IFS= read -r pack_file; do
                local file_size=\$(sudo stat -c '%s' "\$pack_file" 2>/dev/null)
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
                
                if [ "\$file_size" -gt "\$SIZE_MAX_BYTES" ]; then
                    flock \${over_max_file}.lock -c "echo \"\$REPO:\$pack_file (\$size_display)\" >> \${over_max_file}.tmp"
                    has_file_over_max=1
                elif [ "\$file_size" -gt "\$SIZE_MIN_BYTES" ]; then
                    flock \${between_file}.lock -c "echo \"\$REPO:\$pack_file (\$size_display)\" >> \${between_file}.tmp"
                    has_file_between=1
                fi
            done <<< "\$large_packs"
        fi
    fi
    
    # Now look for other large files (skip objects/pack since we already processed those)
    # Use timeout to avoid hanging on problematic repositories
    local large_files=\$(timeout \${FIND_TIMEOUT:-60} sudo find \$REPO -path "\$REPO/objects/pack" -prune -o -type f -size +\${SIZE_MIN_MB}M -print 2>/dev/null)
    
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
            
            if [ "\$file_size" -gt "\$SIZE_MAX_BYTES" ]; then
                flock \${over_max_file}.lock -c "echo \"\$REPO:\$file (\$size_display)\" >> \${over_max_file}.tmp"
                has_file_over_max=1
            elif [ "\$file_size" -gt "\$SIZE_MIN_BYTES" ]; then
                flock \${between_file}.lock -c "echo \"\$REPO:\$file (\$size_display)\" >> \${between_file}.tmp"
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
process_one_repo "\$1" "\$2" "\$3"
EOL
    chmod +x /tmp/repo_processor.$$.sh
    
    # Use parallel with the temp script instead of the function directly
    echo "$REPOS_TO_PROCESS" | parallel --will-cite -j "$PARALLEL_JOBS" \
        "/bin/bash /tmp/repo_processor.$$.sh {} {#} $TOP_REPOS_COUNT"
    
    # Clean up
    rm -f /tmp/repo_processor.$$.sh
else
    # Process sequentially
    repo_count=0
    for REPO in $REPOS_TO_PROCESS; do
        repo_count=$((repo_count + 1))
        process_repo "$REPO" "$repo_count" "$TOP_REPOS_COUNT"
        
        # Show progress every 10 repositories
        if [ $((repo_count % 10)) -eq 0 ]; then
            echo "Progress: $repo_count/$TOP_REPOS_COUNT repositories processed"
        fi
    done
fi

# Now read back the repository IDs from the temporary files
readarray -t repo_ids_over_max < /tmp/repo_ids_over_max.list
readarray -t repo_ids_between < /tmp/repo_ids_between.list

# Create a lookup table for repository names if it doesn't already exist
if [ ! -f /tmp/repo_nwo_lookup.$$ ] && command -v ghe-nwo &> /dev/null; then
    # Ensure the file exists even if process_repo didn't create it (parallel mode)
    touch /tmp/repo_nwo_lookup.$$
    
    # Get names for any repositories we haven't already looked up
    for repo_path in "${repo_ids_over_max[@]}" "${repo_ids_between[@]}"; do
        if ! grep -q "^$repo_path:" /tmp/repo_nwo_lookup.$$ 2>/dev/null; then
            repo_name=$(extract_repo_name "$repo_path")
            nwo=$(sudo ghe-nwo "$repo_path" 2>/dev/null)
            if [ -n "$nwo" ]; then
                echo "$repo_path:$nwo" >> /tmp/repo_nwo_lookup.$$
            else
                echo "$repo_path:$repo_name" >> /tmp/repo_nwo_lookup.$$
            fi
        fi
    done
fi

# Clean up temporary files
rm -f ${over_max_file}.lock ${between_file}.lock
rm -f /tmp/repo_ids_over_max.lock /tmp/repo_ids_between.lock
rm -f /tmp/repo_ids_over_max.list /tmp/repo_ids_between.list
rm -f "$ACTIVE_REPOS_FILE" "$TOP_REPOS_FILE" "$ALL_REPOS_SIZES_FILE"
rm -f /tmp/repo_processor.$$.sh 2>/dev/null

# Keep the repository lookup file for the final pass of fixing repository names
# It will be cleaned up at the end

# Post-processing: Convert repository IDs to names using ghe-nwo
echo "Converting repository IDs to human-readable names..."
repos_over_max=""
repos_between=""

if command -v ghe-nwo &> /dev/null; then
    # Process repositories with files over max size
    if [ ${#repo_ids_over_max[@]} -gt 0 ]; then
        echo "Processing ${#repo_ids_over_max[@]} repositories with large files..."
        for repo in "${repo_ids_over_max[@]}"; do
            repo_name=$(extract_repo_name "$repo")
            nwo=$(sudo ghe-nwo "$repo" 2>/dev/null)
            if [ -n "$nwo" ]; then
                repos_over_max="$repos_over_max $nwo"
                # Replace repo ID with NWO in temp file - use a more specific pattern to avoid partial matches
                sudo sed -i "s|^$repo:|$nwo:|g" ${over_max_file}.tmp
                # Make a second pass to catch any instances where the path might be double-quoted
                sudo sed -i "s|\"$repo:|\"$nwo:|g" ${over_max_file}.tmp
            else
                repos_over_max="$repos_over_max $repo_name"
            fi
        done
    fi
    
    # Process repositories with files between min and max size
    if [ ${#repo_ids_between[@]} -gt 0 ]; then
        echo "Processing ${#repo_ids_between[@]} repositories with medium files..."
        for repo in "${repo_ids_between[@]}"; do
            repo_name=$(extract_repo_name "$repo")
            nwo=$(sudo ghe-nwo "$repo" 2>/dev/null)
            if [ -n "$nwo" ]; then
                repos_between="$repos_between $nwo"
                # Replace repo ID with NWO in temp file - use a more specific pattern to avoid partial matches
                sudo sed -i "s|^$repo:|$nwo:|g" ${between_file}.tmp
                # Make a second pass to catch any instances where the path might be double-quoted
                sudo sed -i "s|\"$repo:|\"$nwo:|g" ${between_file}.tmp
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

# Fix any problematic paths in the output files
if command -v ghe-nwo &> /dev/null; then
    echo "Fixing repository paths in output files..."
    # Process each file line by line and ensure repository paths are properly named
    for output_file in "$over_max_file" "$between_file"; do
        if [ -f "$output_file" ]; then
            tmp_fixed_file="${output_file}.fixed"
            > "$tmp_fixed_file"
            
            while IFS= read -r line; do
                # Extract repository path - handle the colon carefully
                repo_path=$(echo "$line" | awk -F: '{print $1}')
                file_info=$(echo "$line" | cut -d':' -f2-)
                
                # If it's a full path that looks like a repository path
                if [[ "$repo_path" == "/data/user/repositories/"* ]]; then
                    # Try to get the friendly name via ghe-nwo
                    nwo=$(sudo ghe-nwo "$repo_path" 2>/dev/null)
                    if [ -n "$nwo" ]; then
                        # Replace with friendly name, but do it safely without sed which can have issues with paths
                        echo "${nwo}:${file_info}" >> "$tmp_fixed_file"
                    else
                        # Keep as is if no friendly name available
                        echo "$line" >> "$tmp_fixed_file"
                    fi
                else
                    # If not a path, keep as is
                    echo "$line" >> "$tmp_fixed_file"
                fi
            done < "$output_file"
            
            # Replace with fixed file
            sudo mv "$tmp_fixed_file" "$output_file"
        fi
    done
fi

# Print summary report
echo "======================================"
echo "REPOSITORY FILE SIZE ANALYSIS SUMMARY"
echo "======================================"
echo "Total repositories found: $TOTAL_REPOS"
echo "Analyzed top $TOP_REPOS_COUNT repositories by size"
echo ""

# Count unique repositories in the results
over_max_repos=$(awk -F: '{print $1}' "$over_max_file" 2>/dev/null | sort -u | wc -l)
between_repos=$(awk -F: '{print $1}' "$between_file" 2>/dev/null | sort -u | wc -l)
over_max_files=$(wc -l < "$over_max_file" 2>/dev/null || echo 0)
between_files=$(wc -l < "$between_file" 2>/dev/null || echo 0)

echo "FINDINGS SUMMARY:"
echo "----------------"
echo "1. Repositories with files > ${SIZE_MAX_MB}MB: $over_max_repos"
echo "   Total files > ${SIZE_MAX_MB}MB: $over_max_files"
echo ""
echo "2. Repositories with files ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $between_repos" 
echo "   Total files ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $between_files"
echo ""

# Show top 5 largest repositories with large files
if [ $over_max_repos -gt 0 ]; then
    echo "TOP 5 REPOSITORIES WITH LARGEST FILES:"
    echo "------------------------------------"
    awk -F: '{print $1}' "$over_max_file" | sort | uniq -c | sort -nr | head -5 | 
    while read count repo; do
        echo "  $repo: $count large files"
    done
    echo ""
fi

echo "REPORTS LOCATION:"
echo "---------------"
echo "* Files over ${SIZE_MAX_MB}MB: $over_max_file"
echo "* Files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB: $between_file"
echo ""
echo "Analysis completed: $(date)"

# Final pass to ensure repository names are properly displayed
if [ -f /tmp/repo_nwo_lookup.$$ ]; then
    echo ""
    echo "Making final pass to ensure repository names are properly displayed..."
    
    # Read in the lookup table
    while IFS=: read -r repo_path repo_name; do
        if [ -n "$repo_path" ] && [ -n "$repo_name" ]; then
            # Replace full paths with friendly names in both output files
            for output_file in "$over_max_file" "$between_file"; do
                if [ -f "$output_file" ]; then
                    # Use safer approach with awk instead of sed for problematic paths
                    # Create a temporary file for the replacements
                    tmp_file="${output_file}.repl"
                    > "$tmp_file"
                    
                    # Process the file line by line
                    while IFS= read -r line; do
                        # Check if the line starts with the repo path
                        if [[ "$line" == "$repo_path:"* ]]; then
                            # Replace with repo name
                            rest_of_line="${line#$repo_path:}"
                            echo "$repo_name:$rest_of_line" >> "$tmp_file"
                        # Check if the line contains the repo path with a space before it
                        elif [[ "$line" == *" $repo_path:"* ]]; then
                            echo "${line/ $repo_path:/ $repo_name:}" >> "$tmp_file"
                        elif [[ "$line" == *" $repo_path/"* ]]; then
                            echo "${line/ $repo_path\// $repo_name\/}" >> "$tmp_file"
                        else
                            # Keep the line as is
                            echo "$line" >> "$tmp_file"
                        fi
                    done < "$output_file"
                    
                    # Replace the original file with the modified file
                    sudo mv "$tmp_file" "$output_file"
                fi
            done
        fi
    done < /tmp/repo_nwo_lookup.$$
    
    # Clean up the lookup table
    rm -f /tmp/repo_nwo_lookup.$$
fi

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
        # trap 'rm -rf "$TEMP_DIR"' EXIT
        # trap 'ls -la "$TEMP_DIR"' EXIT
        
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
