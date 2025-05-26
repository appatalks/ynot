#!/bin/bash
# Script to process repo-filesize-analysis.sh output files and resolve Git pack objects

# Default values
INPUT_FILE=""
REPOSITORY_BASE="/data/user/repositories"
MIN_SIZE_MB=1
TOP_OBJECTS=10
PARALLEL_JOBS=4

# Help function
show_help() {
    echo "Usage: $0 -f <input_file> [-b <repository_base_path>] [-m <min_size_MB>] [-t <top_objects>] [-j <parallel_jobs>]"
    echo ""
    echo "Options:"
    echo "  -f  Input file (output of repo-filesize-analysis.sh)"
    echo "  -b  Base path for repositories (default: /data/user/repositories)"
    echo "  -m  Minimum file size in MB to show (default: 1)"
    echo "  -t  Number of top objects to display per pack (default: 10)"
    echo "  -j  Number of parallel jobs (default: 4)"
    echo "  -h  Show this help"
    echo ""
    echo "Example:"
    echo "  $0 -f /tmp/repos_100mb_to_400mb.txt"
    exit 1
}

# Parse arguments
while getopts "f:b:m:t:j:h" opt; do
    case $opt in
        f) INPUT_FILE="$OPTARG" ;;
        b) REPOSITORY_BASE="$OPTARG" ;;
        m) MIN_SIZE_MB="$OPTARG" ;;
        t) TOP_OBJECTS="$OPTARG" ;;
        j) PARALLEL_JOBS="$OPTARG" ;;
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
OUTPUT_FILE="${INPUT_FILE%.*}_resolved.txt"
> "$OUTPUT_FILE"

# Count total entries
TOTAL_ENTRIES=$(wc -l < "$INPUT_FILE")
echo "Processing $TOTAL_ENTRIES pack files from $INPUT_FILE"
echo "Results will be saved to $OUTPUT_FILE"
echo ""

# Process each line in the input file
processed=0
cat "$INPUT_FILE" | while read -r line; do
    # Split the line at the colon for repo_name and file_info
    repo_name=$(echo "$line" | cut -d':' -f1 | xargs)
    file_info=$(echo "$line" | cut -d':' -f2- | xargs)
    
    # Extract the pack file name and size
    if [[ "$file_info" =~ (objects/pack/pack-[^[:space:]]+) ]]; then
        pack_file=${BASH_REMATCH[1]}
        
        # Extract the size portion, which should be in parentheses at the end
        if [[ "$file_info" =~ \(([0-9]+[[:space:]]*[A-Za-z]+)\) ]]; then
            size="${BASH_REMATCH[1]}"
        else
            size="unknown"
        fi
        
        # Handle both formats: directory path or organization/repo format
        if [[ "$repo_name" == */* ]]; then
            # This is likely an org/repo format
            repo_org=$(echo "$repo_name" | cut -d'/' -f1)
            repo_project=$(echo "$repo_name" | cut -d'/' -f2-)
            
            # Most likely path format based on standard GitHub Enterprise structure
            repo_path="${REPOSITORY_BASE}/${repo_name}.git"
            
            # Only if that doesn't exist, try the alternative paths
            if ! sudo test -d "$repo_path"; then
                if sudo test -d "${REPOSITORY_BASE}/${repo_org}/${repo_project}.git"; then
                    repo_path="${REPOSITORY_BASE}/${repo_org}/${repo_project}.git"
                elif sudo test -d "${REPOSITORY_BASE}/${repo_name}"; then
                    repo_path="${REPOSITORY_BASE}/${repo_name}"
                fi
                # If still not found, we'll stick with the default
            fi
        else
            # This is a direct path reference
            repo_path="${REPOSITORY_BASE}/${repo_name}"
            if ! sudo test -d "$repo_path"; then
                # Try with .git extension
                if sudo test -d "${repo_path}.git"; then
                    repo_path="${repo_path}.git"
                fi
            fi
        fi
        
        pack_path="${repo_path}/${pack_file}"
        
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
                
                # Run the resolver script with sudo
                echo "Running resolver with sudo..."
                sudo "$RESOLVER_SCRIPT" -p "$pack_path" -r "$repo_path" -m "$MIN_SIZE_MB" -t "$TOP_OBJECTS" >> "$OUTPUT_FILE" 2>&1
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
            echo "  Repository path: $repo_path" >> "$OUTPUT_FILE"
            
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
        
        # Try to extract any .pack or .idx reference
        if [[ "$line" =~ (pack-[[:alnum:]]+\.(pack|idx)) ]]; then
            potential_pack="${BASH_REMATCH[1]}"
            echo "Potential pack file reference found: $potential_pack" >> "$OUTPUT_FILE"
            
            # Try to find this in the repositories
            echo "Searching for this pack file in repositories..." >> "$OUTPUT_FILE"
            search_result=$(sudo find "${REPOSITORY_BASE}" -name "$potential_pack" -type f 2>/dev/null | head -3)
            if [ -n "$search_result" ]; then
                echo "Found in:" >> "$OUTPUT_FILE"
                echo "$search_result" >> "$OUTPUT_FILE"
            else
                echo "Not found in repository storage." >> "$OUTPUT_FILE"
            fi
        fi
        
        echo "" >> "$OUTPUT_FILE"
        echo "----------------------------------------" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

echo "Processing complete. Results saved to $OUTPUT_FILE"
