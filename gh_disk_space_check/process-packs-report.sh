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
cat "$INPUT_FILE" | while IFS=: read -r repo_name file_info; do
    # Extract the pack file name and size
    if [[ "$file_info" =~ objects/pack/pack-.*\.pack ]]; then
        pack_file=$(echo "$file_info" | awk '{print $1}' | xargs)
        size=$(echo "$file_info" | awk '{print $2, $3}' | tr -d '()' | xargs)
        
        # Construct the full path to the repository
        repo_path="${REPOSITORY_BASE}/${repo_name}.git"
        pack_path="${repo_path}/${pack_file}"
        
        processed=$((processed+1))
        echo "[$processed/$TOTAL_ENTRIES] Processing: $repo_name - $pack_file ($size)"
        
        # Check if repository and pack file exist
        if [ -d "$repo_path" ] && [ -f "$pack_path" ]; then
            echo "==== Repository: $repo_name ====" >> "$OUTPUT_FILE"
            echo "Pack file: $pack_file ($size)" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            # Run the resolver script
            "$RESOLVER_SCRIPT" -p "$pack_path" -r "$repo_path" -m "$MIN_SIZE_MB" -t "$TOP_OBJECTS" >> "$OUTPUT_FILE" 2>&1
            echo "" >> "$OUTPUT_FILE"
            echo "----------------------------------------" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        else
            echo "==== Repository: $repo_name ====" >> "$OUTPUT_FILE"
            echo "ERROR: Repository or pack file not found:" >> "$OUTPUT_FILE"
            echo "  Repository path: $repo_path" >> "$OUTPUT_FILE"
            echo "  Pack file: $pack_path" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            echo "----------------------------------------" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    else
        echo "Warning: Line does not contain a pack file reference: $repo_name:$file_info"
    fi
done

echo "Processing complete. Results saved to $OUTPUT_FILE"
