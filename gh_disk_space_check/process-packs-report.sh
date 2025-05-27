#!/bin/bash
# Script to process repo-filesize-analysis.sh output files and resolve Git pack objects
# 
# May 2025 update: Fixed path duplication issue that caused errors like:
# "Repository not found: /data/user/repositories//data/user/repositories/path/to/repo"
# Added clean_repo_path function to normalize paths and detect/fix path duplications

# Default values
INPUT_FILE=""
REPOSITORY_BASE="/data/user/repositories"
MIN_SIZE_MB=1
TOP_OBJECTS=10
PARALLEL_JOBS=4
VERBOSE=0

# Help function
show_help() {
    echo "Usage: $0 -f <input_file> [-b <repository_base_path>] [-m <min_size_MB>] [-t <top_objects>] [-j <parallel_jobs>] [-v]"
    echo ""
    echo "Options:"
    echo "  -f  Input file (output of repo-filesize-analysis.sh)"
    echo "  -b  Base path for repositories (default: /data/user/repositories)"
    echo "  -m  Minimum file size in MB to show (default: 1)"
    echo "  -t  Number of top objects to display per pack (default: 10)"
    echo "  -j  Number of parallel jobs (default: 4)"
    echo "  -v  Verbose output (show path corrections)"
    echo "  -h  Show this help"
    echo ""
    echo "Example:"
    echo "  $0 -f /tmp/repos_100mb_to_400mb.txt"
    exit 1
}

# Parse arguments
while getopts "f:b:m:t:j:vh" opt; do
    case $opt in
        f) INPUT_FILE="$OPTARG" ;;
        b) REPOSITORY_BASE="$OPTARG" ;;
        m) MIN_SIZE_MB="$OPTARG" ;;
        t) TOP_OBJECTS="$OPTARG" ;;
        j) PARALLEL_JOBS="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h) show_help ;;
        *) show_help ;;
    esac
done

# Validate required parameter
if [ -z "$INPUT_FILE" ]; then
    echo "Error: Input file (-f) is required"
    show_help
fi

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    exit 1
fi

# Check if resolve-pack-objects.sh exists and is executable
RESOLVER_SCRIPT="$(dirname "$0")/resolve-pack-objects.sh"

if [ ! -f "$RESOLVER_SCRIPT" ] || [ ! -x "$RESOLVER_SCRIPT" ]; then
    echo "resolve-pack-objects.sh not found in the same directory. Attempting to download it..."
    
    # Create a temporary directory if needed
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    
    # Download the required script
    curl -s -L "https://raw.githubusercontent.com/appatalks/ynot/refs/heads/main/gh_disk_space_check/resolve-pack-objects.sh" -o "${TEMP_DIR}/resolve-pack-objects.sh"
    chmod +x "${TEMP_DIR}/resolve-pack-objects.sh"
    
    if [ -f "${TEMP_DIR}/resolve-pack-objects.sh" ] && [ -x "${TEMP_DIR}/resolve-pack-objects.sh" ]; then
        echo "Successfully downloaded resolve-pack-objects.sh"
        RESOLVER_SCRIPT="${TEMP_DIR}/resolve-pack-objects.sh"
    else
        echo "Error: Failed to download resolve-pack-objects.sh"
        exit 1
    fi
fi

# Output file
# Check if the input file name already contains _resolved.txt
if [[ "$INPUT_FILE" == *"_resolved.txt" ]]; then
    # If it does, remove any .txt suffix and append _final.txt
    OUTPUT_FILE="${INPUT_FILE%_resolved.txt}_final.txt"
    if [[ "$OUTPUT_FILE" == *".txt"* ]]; then
        OUTPUT_FILE="${OUTPUT_FILE%.txt}_final.txt"
    else
        OUTPUT_FILE="${OUTPUT_FILE}_final.txt"
    fi
# Check if it has a .txt extension
elif [[ "$INPUT_FILE" == *.txt ]]; then
    # Regular case, remove .txt and add _resolved.txt
    OUTPUT_FILE="${INPUT_FILE%.txt}_resolved.txt"
else
    # No .txt extension, just add _resolved.txt
    OUTPUT_FILE="${INPUT_FILE}_resolved.txt"
fi
> "$OUTPUT_FILE"

# Count total entries
TOTAL_ENTRIES=$(wc -l < "$INPUT_FILE")
echo "Processing $TOTAL_ENTRIES pack files from $INPUT_FILE"
echo "Results will be saved to $OUTPUT_FILE"
echo ""

# First, analyze the input file to group entries by repository
echo "Analyzing input file and grouping by repository..."
declare -A repo_entries
declare -A repo_sizes
total_lines=0

while IFS= read -r line; do
    # Split the line at the colon for repo_name and file_info
    repo_name=$(echo "$line" | cut -d':' -f1 | xargs)
    file_info=$(echo "$line" | cut -d':' -f2- | xargs)
    
    # Extract size if available
    if [[ "$file_info" =~ \(([0-9]+)[[:space:]]*[A-Za-z]+\) ]]; then
        size=${BASH_REMATCH[1]}
        
        # Add to the repository's total size
        current_size=${repo_sizes[$repo_name]:-0}
        repo_sizes[$repo_name]=$((current_size + size))
    fi
    
    # Count entries per repository
    repo_entries[$repo_name]=$((${repo_entries[$repo_name]:-0} + 1))
    total_lines=$((total_lines + 1))
done < "$INPUT_FILE"

# Sort repositories by size for intelligent prioritization
echo "Sorting repositories by total size to prioritize processing..."
declare -a sorted_repos=()

# Create a temporary file for sorting
tmp_sort_file=$(mktemp)
for repo_name in "${!repo_sizes[@]}"; do
    echo "${repo_sizes[$repo_name]} $repo_name" >> "$tmp_sort_file"
done

# Sort by size in descending order and extract repo names
readarray -t sorted_repos < <(sort -nr "$tmp_sort_file" | awk '{print $2}')
rm -f "$tmp_sort_file"

# Display top 5 largest repositories for context
echo "Top 5 largest repositories (by pack file size):"
for ((i=0; i<5 && i<${#sorted_repos[@]}; i++)); do
    repo="${sorted_repos[$i]}"
    size_mb=$((${repo_sizes[$repo]} / 1024 / 1024))
    echo "  $repo: ${size_mb}MB (${repo_entries[$repo]} pack files)"
done
echo ""
echo "Found $total_lines entries across ${#repo_entries[@]} repositories"
echo "Prioritizing repositories with the largest objects..."

# Create a priority list of repositories
priority_repos=$(
    for repo in "${!repo_sizes[@]}"; do
        echo "$repo ${repo_sizes[$repo]}"
    done | sort -k2,2nr | head -20 | awk '{print $1}'
)

# Function to clean up repository paths with potential duplications
clean_repo_path() {
    local path="$1"
    local repo_base="${REPOSITORY_BASE:-/data/user/repositories}"
    local original_path="$path"
    
    # First, normalize the path by removing trailing slashes
    path="${path%/}"
    
    # Remove any duplicate repository base paths (handles multiple occurrences)
    while [[ "$path" == *"$repo_base"*"$repo_base"* ]]; do
        # Get the substring starting with the pattern
        local duplicate_part="${path#*$repo_base}"
        # If the substring starts with the pattern again, remove it
        if [[ "$duplicate_part" == "$repo_base"* ]]; then
            path="${path/$repo_base$duplicate_part/$duplicate_part}"
        else
            break
        fi
    done
    
    # Special case for hardcoded paths vs variable
    if [[ "$repo_base" != "/data/user/repositories" ]]; then
        # Check for hardcoded path duplication
        while [[ "$path" == *"/data/user/repositories"*"/data/user/repositories"* ]]; do
            path="${path//\/data\/user\/repositories\/\/data\/user\/repositories\//\/data\/user\/repositories\/}"
        done
    fi
    
    # Handle any double slash scenarios that might occur during replacements
    while [[ "$path" == *"//"* ]]; do
        path="${path//\/\//\/}"
    done
    
    # Ensure .git suffix isn't duplicated
    if [[ "$path" == *".git.git" ]]; then
        path="${path%.git.git}.git"
    fi
    
    # Debug log if we fixed something
    if [[ "$path" != "$original_path" ]] && [[ "$VERBOSE" -eq 1 ]]; then
        echo "Path fixed: $original_path -> $path" >&2
    fi
    
    echo "$path"
}

# Process each line in the input file
processed=0
cat "$INPUT_FILE" | while read -r line; do
    # Split the line at the colon for repo_name and file_info
    repo_name=$(echo "$line" | cut -d':' -f1 | xargs)
    file_info=$(echo "$line" | cut -d':' -f2- | xargs)
    
    # Handle case where repository path is duplicated in the file information
    if [[ "$file_info" == "$repo_name/"* ]] || [[ "$file_info" == "$repo_name:"* ]]; then
        # Fix duplicated repository path in file_info
        file_info=$(echo "$file_info" | sed "s|^$repo_name[/:]||")
    fi
    
    # Special case handling for repository paths that contain full path twice
    if [[ "$file_info" == *"/data/user/repositories/"* ]]; then
        # Clean up duplicated path segments
        file_info=$(echo "$file_info" | sed 's|/data/user/repositories/||g')
        if [[ ! "$file_info" == objects/pack/* ]]; then
            # Ensure correct format if not already prefixed
            file_info="objects/pack/$file_info"
        fi
    fi
    
    # Handle malformed file info that doesn't include objects/pack prefix
    if [[ "$file_info" == pack-*.pack* && ! "$file_info" == objects/pack/* ]]; then
        file_info="objects/pack/$file_info"
    fi
    
    # Extract the pack file name and size
    if [[ "$file_info" =~ (objects/pack/pack-[^[:space:]]+\.pack) ]]; then
        pack_file=${BASH_REMATCH[1]}
    # Try an alternative pattern for pack files that may be missing the .pack extension
    elif [[ "$file_info" =~ (objects/pack/pack-[0-9a-f]+) ]]; then
        pack_file="${BASH_REMATCH[1]}.pack"
        echo "Added .pack extension to: $pack_file" >&2
        
        # Extract the size portion, which should be in parentheses at the end
        if [[ "$file_info" =~ \(([0-9]+[[:space:]]*[A-Za-z]+)\) ]]; then
            size="${BASH_REMATCH[1]}"
        else
            size="unknown"
        fi
        
        # Skip low priority repositories if we have too many entries
        if [ ${#repo_entries[@]} -gt 10 ] && ! echo "$priority_repos" | grep -q "^$repo_name$"; then
            continue
        fi
        
        # Handle both formats: directory path or organization/repo format
        if [[ "$repo_name" == */* ]]; then
            # Check if the repo_name already has the repository base path included
            if [[ "$repo_name" == "$REPOSITORY_BASE"* ]] || [[ "$repo_name" == "/data/user/repositories/"* ]]; then
                # Already has the base path, use as is but clean up any duplications
                repo_path=$(clean_repo_path "$repo_name")
                
                # Check if it's a valid path
                if ! sudo test -d "$repo_path"; then
                    # Try adding .git if needed
                    if sudo test -d "${repo_path}.git"; then
                        repo_path="${repo_path}.git"
                    fi
                fi
            else
                # This is likely an org/repo format without base path
                repo_org=$(echo "$repo_name" | cut -d'/' -f1)
                repo_project=$(echo "$repo_name" | cut -d'/' -f2-)
                
                # Most likely path format based on standard GitHub Enterprise structure
                repo_path=$(clean_repo_path "${REPOSITORY_BASE}/${repo_name}.git")
                
                # Only if that doesn't exist, try the alternative paths
                if ! sudo test -d "$repo_path"; then
                    if sudo test -d $(clean_repo_path "${REPOSITORY_BASE}/${repo_org}/${repo_project}.git"); then
                        repo_path=$(clean_repo_path "${REPOSITORY_BASE}/${repo_org}/${repo_project}.git")
                    elif sudo test -d $(clean_repo_path "${REPOSITORY_BASE}/${repo_name}"); then
                        repo_path=$(clean_repo_path "${REPOSITORY_BASE}/${repo_name}")
                    fi
                    # If still not found, we'll stick with the default
                fi
            fi
        else
            # This is a direct path reference
            # Check if repo_name already has the REPOSITORY_BASE or a hardcoded base path as a prefix
            if [[ "$repo_name" == "$REPOSITORY_BASE"* ]] || [[ "$repo_name" == "/data/user/repositories/"* ]]; then
                # Already has a base path, use as is but clean up any duplications
                repo_path=$(clean_repo_path "$repo_name")
            else
                # No base path, add it
                repo_path=$(clean_repo_path "${REPOSITORY_BASE}/${repo_name}")
            fi
            
            if ! sudo test -d "$repo_path"; then
                # Try with .git extension
                if sudo test -d "${repo_path}.git"; then
                    repo_path="${repo_path}.git"
                fi
            fi
        fi
        
        # Ensure repo_path and pack_path are clean
        repo_path=$(clean_repo_path "$repo_path")
        pack_path=$(clean_repo_path "${repo_path}/${pack_file}")
        
        processed=$((processed+1))
        echo "[$processed/$TOTAL_ENTRIES] Processing: $repo_name - $pack_file ($size)"
        
        echo "==== Repository: $repo_name ====" >> "$OUTPUT_FILE"
        echo "Pack file: $pack_file ($size)" >> "$OUTPUT_FILE"
        
        # Use sudo to check if repository and pack file exist
        if sudo test -d "$repo_path"; then
            # Repository exists
            if sudo test -f "$pack_path"; then
                echo "Repository path: $repo_path" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
                
                # Run the resolver script with sudo and dynamic TOP_OBJECTS adjustment
                echo "Running resolver with sudo..."
                
                # Dynamic TOP_OBJECTS adjustment based on repository context
                adjusted_top_objects=$TOP_OBJECTS
                
                # Adjust based on repository size
                repo_size=${repo_sizes[$repo_name]:-0}
                repo_size_mb=$((repo_size / 1024 / 1024))
                
                # If this is a very large repo, reduce the number of objects to extract
                if [ "$repo_size_mb" -gt 1000 ]; then # >1GB
                    adjusted_top_objects=3
                elif [ "$repo_size_mb" -gt 500 ]; then # >500MB
                    adjusted_top_objects=5
                elif [ "$repo_size_mb" -gt 250 ]; then # >250MB
                    adjusted_top_objects=7
                fi
                
                # Further adjust based on total repository count
                if [ ${#repo_entries[@]} -gt 50 ] && [ "$adjusted_top_objects" -gt 5 ]; then
                    adjusted_top_objects=5  # Many repositories, be more selective
                fi
                
                # Check if this is a priority repository and give more objects for high-priority repos
                if echo "$priority_repos" | grep -q "^$repo_name$" && [ "${#sorted_repos[@]}" -le 10 ]; then
                    # For top priority repos in small installations, allow more objects
                    adjusted_top_objects=$TOP_OBJECTS
                fi
                
                # Run the resolver with the adjusted value and batch mode for performance
                echo "Using TOP_OBJECTS=$adjusted_top_objects for this repository (default=$TOP_OBJECTS)" >> "$OUTPUT_FILE"
                
                # Enable batch mode for improved performance with multiple pack files
                # This allows caching repository data between multiple pack file analyses
                if [ ${#repo_entries[@]} -gt 3 ]; then
                    echo "Enabling batch mode for more efficient processing" >> "$OUTPUT_FILE"
                    sudo "$RESOLVER_SCRIPT" -p "$pack_path" -r "$repo_path" -m "$MIN_SIZE_MB" -t "$adjusted_top_objects" -b -T 60 >> "$OUTPUT_FILE" 2>&1
                else
                    # For repositories with few pack files, batch mode overhead isn't worth it
                    sudo "$RESOLVER_SCRIPT" -p "$pack_path" -r "$repo_path" -m "$MIN_SIZE_MB" -t "$adjusted_top_objects" >> "$OUTPUT_FILE" 2>&1
                fi
            else
                echo "ERROR: Pack file not found. Repository exists but the pack file does not:" >> "$OUTPUT_FILE"
                echo "  Repository path: $repo_path" >> "$OUTPUT_FILE"
                echo "  Pack file: $pack_path" >> "$OUTPUT_FILE"
                
                # List available pack files
                echo "" >> "$OUTPUT_FILE"
                echo "Available pack files in repository:" >> "$OUTPUT_FILE"
                sudo find "$repo_path/objects/pack" -name "*.pack" -type f 2>/dev/null | sudo xargs -r ls -lah 2>/dev/null >> "$OUTPUT_FILE"
            fi
        else
            echo "ERROR: Repository not found:" >> "$OUTPUT_FILE"
            echo "  Original repo name: $repo_name" >> "$OUTPUT_FILE"
            echo "  Repository path: $repo_path" >> "$OUTPUT_FILE"
            
            # Store the original path for comparison
            original_path="$repo_path"
            attempted_path="$repo_path"
            found_path=false
            
            # If there's path duplication, highlight this as a potential issue
            if [[ "$original_path" != "$(clean_repo_path "$original_path")" ]]; then
                echo "  WARNING: Potential path duplication or format issue detected" >> "$OUTPUT_FILE"
                # Show a corrected path for reference
                corrected_path=$(clean_repo_path "$original_path")
                echo "  Corrected path would be: $corrected_path" >> "$OUTPUT_FILE"
                
                # Try a series of corrections to find a valid path
                
                # Check if the corrected path exists
                if sudo test -d "$corrected_path"; then
                    echo "  NOTE: The corrected path exists in the filesystem" >> "$OUTPUT_FILE"
                    attempted_path="$corrected_path"
                    found_path=true
                # Check with .git suffix
                elif sudo test -d "${corrected_path}.git"; then
                    echo "  NOTE: The corrected path with .git suffix exists in the filesystem" >> "$OUTPUT_FILE" 
                    attempted_path="${corrected_path}.git"
                    found_path=true
                # Try removing any remaining duplicate segments
                elif [[ "$corrected_path" == *"/data/user/repositories"*"/data/user/repositories"* ]]; then
                    stripped_path="${corrected_path//\/data\/user\/repositories\//\/}"
                    stripped_path="/data/user/repositories${stripped_path#*/}"
                    echo "  Trying stripped path: $stripped_path" >> "$OUTPUT_FILE"
                    if sudo test -d "$stripped_path"; then
                        echo "  Success! Stripped path exists" >> "$OUTPUT_FILE"
                        attempted_path="$stripped_path"
                        found_path=true
                    fi
                fi
                
                # If we found a working path, offer helpful information and try to process it
                if [ "$found_path" = true ] && [[ "$attempted_path" != "$original_path" ]]; then
                    echo "  RESOLUTION: The correct working path appears to be: $attempted_path" >> "$OUTPUT_FILE"
                    echo "  Please check your input file format to prevent path duplication issues" >> "$OUTPUT_FILE"
                    
                    # Try to process the pack file at the corrected location 
                    corrected_pack_path="$attempted_path/$pack_file"
                    if sudo test -f "$corrected_pack_path"; then
                        echo "" >> "$OUTPUT_FILE"
                        echo "Attempting to process with the corrected path:" >> "$OUTPUT_FILE"
                        
                        # Run the resolver with the corrected path
                        adjusted_top_objects=$TOP_OBJECTS
                        
                        # Get approximate repository size (if not already defined)
                        if [ -z "$repo_size_mb" ]; then
                            repo_size_kb=$(sudo du -sk "$attempted_path" 2>/dev/null | awk '{print $1}')
                            repo_size_mb=$((repo_size_kb / 1024))
                        fi
                        
                        # Adjust objects based on repo size
                        if [ "$repo_size_mb" -gt 500 ]; then
                            adjusted_top_objects=5
                        fi
                        
                        echo "Using TOP_OBJECTS=$adjusted_top_objects for this repository" >> "$OUTPUT_FILE"
                        sudo "$RESOLVER_SCRIPT" -p "$corrected_pack_path" -r "$attempted_path" -m "$MIN_SIZE_MB" -t "$adjusted_top_objects" -T 60 >> "$OUTPUT_FILE" 2>&1
                    else
                        echo "  The pack file was not found at the corrected location: $corrected_pack_path" >> "$OUTPUT_FILE"
                    fi
                fi
            fi
            
            # Try to find similar repositories
            echo "" >> "$OUTPUT_FILE"
            echo "Searching for similar repositories:" >> "$OUTPUT_FILE"
            if [[ "$repo_name" == */* ]]; then
                repo_org=$(echo "$repo_name" | cut -d'/' -f1)
                sudo find "${REPOSITORY_BASE}" -name "${repo_org}*" -type d 2>/dev/null | head -5 >> "$OUTPUT_FILE"
            fi
        fi
        
        echo "" >> "$OUTPUT_FILE"
        echo "----------------------------------------" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        echo "Warning: Line does not contain a recognized pack file reference: $line"
        
        echo "==== Unrecognized format ====" >> "$OUTPUT_FILE"
        echo "Original line: $line" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        # Try to extract any .pack or .idx reference or any Git SHA reference
        if [[ "$line" =~ (pack-[[:alnum:]]+\.(pack|idx)) ]]; then
            potential_pack="${BASH_REMATCH[1]}"
            echo "Potential pack file reference found: $potential_pack" >> "$OUTPUT_FILE"
            
            # Try to find this in the repositories
            echo "Searching for this pack file in repositories..." >> "$OUTPUT_FILE"
            search_result=$(sudo find "${REPOSITORY_BASE}" -name "$potential_pack" -type f 2>/dev/null | head -3)
            if [ -n "$search_result" ]; then
                echo "Found in:" >> "$OUTPUT_FILE"
                echo "$search_result" >> "$OUTPUT_FILE"
                
                # Try to process this pack file directly
                for found_pack in $search_result; do
                    echo "Attempting to process found pack: $found_pack" >> "$OUTPUT_FILE"
                    # Extract repository path from the found pack path
                    repo_path=$(echo "$found_pack" | sed -E 's|(.*)/objects/pack/.*|\1|')
                    if [ -d "$repo_path" ]; then
                        echo "Using repository: $repo_path" >> "$OUTPUT_FILE"
                        sudo "$RESOLVER_SCRIPT" -p "$found_pack" -r "$repo_path" -m "$MIN_SIZE_MB" -t "$TOP_OBJECTS" -T 30 >> "$OUTPUT_FILE" 2>&1
                    fi
                    break # Just process the first one we find
                done
            else
                echo "Not found in repository storage." >> "$OUTPUT_FILE"
            fi
        # Try to find Git SHA references that might be pack objects
        elif [[ "$line" =~ ([0-9a-f]{40}) ]]; then
            potential_sha="${BASH_REMATCH[1]}"
            echo "Potential Git SHA reference found: $potential_sha" >> "$OUTPUT_FILE"
            echo "This might be a Git object. If you know which repository it belongs to," >> "$OUTPUT_FILE"
            echo "you can run: git -C /path/to/repo log --all --find-object=$potential_sha" >> "$OUTPUT_FILE"
        fi
        
        echo "" >> "$OUTPUT_FILE"
        echo "----------------------------------------" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

# Verify the output file has content and provide helpful feedback
OUTPUT_SIZE=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")

if [ "$OUTPUT_SIZE" -gt 10 ]; then
    echo "Processing complete. Results saved to $OUTPUT_FILE ($OUTPUT_SIZE lines)"
    
    # Count how many repositories were successfully processed vs. failed
    SUCCESSFUL_REPOS=$(grep -c "Running resolver with sudo..." "$OUTPUT_FILE")
    NOT_FOUND_REPOS=$(grep -c "ERROR: Repository not found:" "$OUTPUT_FILE")
    NOT_FOUND_PACKS=$(grep -c "ERROR: Pack file not found" "$OUTPUT_FILE")
    
    echo "Summary:"
    echo "- Successfully processed pack files: $SUCCESSFUL_REPOS"
    echo "- Repositories not found: $NOT_FOUND_REPOS"
    echo "- Pack files not found: $NOT_FOUND_PACKS"
    
    if [ "$SUCCESSFUL_REPOS" -eq 0 ] && [ "$NOT_FOUND_REPOS" -gt 0 ]; then
        echo "WARNING: No repositories were successfully processed."
        echo "         This may be due to path issues or deleted repositories."
        echo "         Check the output file for details and try running again with -v for verbose output."
    fi
else
    echo "WARNING: Output file contains very little data ($OUTPUT_SIZE lines)."
    echo "         There might be an issue with the input file format or repository paths."
    echo "         Try running with -v for verbose output to see path correction information."
    
    # Add some basic information to the output file so it's not empty
    echo "=== PROCESSING RESULTS ====" >> "$OUTPUT_FILE"
    echo "No pack files were successfully processed." >> "$OUTPUT_FILE"
    echo "This could be due to:" >> "$OUTPUT_FILE"
    echo "1. Repository paths in the input file are incorrect or have format issues" >> "$OUTPUT_FILE"
    echo "2. The repositories no longer exist on this server" >> "$OUTPUT_FILE"
    echo "3. The pack files specified no longer exist" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "Try running: bash $0 -f \"$INPUT_FILE\" -v" >> "$OUTPUT_FILE"
    echo "to see more detailed error information." >> "$OUTPUT_FILE"
fi
