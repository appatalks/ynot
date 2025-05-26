#!/bin/bash
# Save as /tmp/repo-filesize-analysis.sh
# Run with: 'sudo bash /tmp/repo-size-analysis.sh'

# Set thresholds in MB
SIZE_MIN_MB=${SIZE_MIN_MB:-100} # Minimum file size to consider
SIZE_MAX_MB=${SIZE_MAX_MB:-400} # Maximum file size to consider
RESOLVE_OBJECTS=${RESOLVE_OBJECTS:-false} # Whether to automatically resolve large Git objects
TOP_OBJECTS=${TOP_OBJECTS:-10} # Number of top objects to show when resolving
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

# Process each repository
echo "Starting repository analysis..."
repo_count=0
for REPO in $REPOS; do
    repo_count=$((repo_count + 1))
    REPO_NAME=$(echo "$REPO" | sed 's|/data/user/repositories/||g' | sed 's|\.git$||g')
    echo "[$repo_count/$TOTAL_REPOS] Checking $REPO_NAME..."
    
    has_file_over_max=0
    has_file_between=0
    
    # Look for loose objects first (simpler for very small repos)
    # Run a simple find command to identify large files by size
    large_files=$(sudo find $REPO -type f -size +${SIZE_MIN_MB}M 2>/dev/null)
    
    if [ -n "$large_files" ]; then
        for file in $large_files; do
            size_bytes=$(sudo stat -c %s "$file" 2>/dev/null)
            if [ -n "$size_bytes" ] && [ "$size_bytes" -gt 0 ]; then
                size_mb=$((size_bytes / 1024 / 1024))
                file_path=$(echo "$file" | sed "s|$REPO/||")
                
                # Determine the proper format for the repo name to appear in output
                display_repo_name="$REPO_NAME"
                
                # If we have ghe-nwo available, try to use it for better repo name display
                if command -v ghe-nwo &> /dev/null; then
                    nwo=$(sudo ghe-nwo "$REPO" 2>/dev/null)
                    if [ -n "$nwo" ]; then
                        display_repo_name="$nwo"
                    fi
                fi
                
                if [ "$size_bytes" -ge "$SIZE_MAX_BYTES" ]; then
                    echo "$display_repo_name: $file_path ($size_mb MB)" >> $over_max_file.tmp
                    files_over_max=$((files_over_max + 1))
                    has_file_over_max=1
                elif [ "$size_bytes" -ge "$SIZE_MIN_BYTES" ]; then
                    echo "$display_repo_name: $file_path ($size_mb MB)" >> $between_file.tmp
                    files_between=$((files_between + 1))
                    has_file_between=1
                fi
            fi
        done
    fi
    
    # If no large files found with direct approach, try git commands
    if [ $has_file_over_max -eq 0 ] && [ $has_file_between -eq 0 ]; then
        if [ -d "$REPO/objects/pack" ]; then
            cd $REPO
            # Check packed objects
            sudo git verify-pack -v objects/pack/pack-*.idx 2>/dev/null | 
            awk -v min_bytes=$SIZE_MIN_BYTES -v max_bytes=$SIZE_MAX_BYTES '
                $3 >= min_bytes {
                    print $1, $3
                }
            ' | while read hash size; do
                # Get filename for the object
                filename=$(sudo git rev-list --objects --all 2>/dev/null | 
                           grep $hash | awk '{print $2}')
                
                if [ -n "$filename" ]; then
                    size_mb=$((size / 1024 / 1024))
                    
                    if [ $size -ge $SIZE_MAX_BYTES ]; then
                        echo "$REPO_NAME: $filename ($size_mb MB)" >> $over_max_file.tmp
                        files_over_max=$((files_over_max + 1))
                        has_file_over_max=1
                    elif [ $size -ge $SIZE_MIN_BYTES ]; then
                        echo "$REPO_NAME: $filename ($size_mb MB)" >> $between_file.tmp
                        files_between=$((files_between + 1))
                        has_file_between=1
                    fi
                fi
            done
        fi
    fi
    
    # Update repository counters
    if [ $has_file_over_max -eq 1 ]; then
        repos_with_files_over_max=$((repos_with_files_over_max + 1))
        repos_with_files_over_min=$((repos_with_files_over_min + 1))
        
        # Store repository ID for later name resolution
        repos_over_max_ids="$repos_over_max_ids $REPO_NAME"
        repo_ids_over_max+=("$REPO")
    elif [ $has_file_between -eq 1 ]; then
        repos_with_files_between=$((repos_with_files_between + 1))
        repos_with_files_over_min=$((repos_with_files_over_min + 1))
        
        # Store repository ID for later name resolution
        repos_between_ids="$repos_between_ids $REPO_NAME"
        repo_ids_between+=("$REPO")
    fi
done

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
        $RESOLVER_SCRIPT -f "$over_max_file" -t "$TOP_OBJECTS"
        
        echo "Starting to resolve objects in files between ${SIZE_MIN_MB}MB-${SIZE_MAX_MB}MB..."
        $RESOLVER_SCRIPT -f "$between_file" -t "$TOP_OBJECTS"
        
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
