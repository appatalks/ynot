#!/bin/bash
# Script to resolve Git pack objects to file paths
# Performance-optimized version - May 2025

# Default values
PACK_FILE=""
REPO_PATH=""
MIN_SIZE_MB=1
SIZE_IN_BYTES=0
TOP_OBJECTS=10
BATCH_MODE=false
TIMEOUT_SECONDS=30 # Default timeout for operations that might hang

# Help function
show_help() {
    echo "Usage: $0 -p <pack_file> -r <repository_path> [-m <min_size_MB>] [-t <top_objects>] [-b] [-T <timeout_sec>]"
    echo ""
    echo "Options:"
    echo "  -p  Full path to the pack file"
    echo "  -r  Path to the Git repository"
    echo "  -m  Minimum file size in MB to show (default: 1)"
    echo "  -t  Number of top objects to display (default: 10)"
    echo "  -b  Enable batch mode (more efficient for multiple runs)"
    echo "  -T  Timeout in seconds for Git operations (default: 30)"
    echo "  -h  Show this help"
    echo ""
    echo "Example:"
    echo "  $0 -p /data/user/repositories/org/repo.git/objects/pack/pack-abcd1234.pack -r /data/user/repositories/org/repo.git"
    exit 1
}

# Parse arguments
while getopts "p:r:m:t:bT:h" opt; do
    case $opt in
        p) PACK_FILE="$OPTARG" ;;
        r) REPO_PATH="$OPTARG" ;;
        m) MIN_SIZE_MB="$OPTARG" ;;
        t) TOP_OBJECTS="$OPTARG" ;;
        b) BATCH_MODE=true ;;
        T) TIMEOUT_SECONDS="$OPTARG" ;;
        h) show_help ;;
        *) show_help ;;
    esac
done

# Validate required parameters
if [ -z "$PACK_FILE" ] || [ -z "$REPO_PATH" ]; then
    echo "Error: Both pack file (-p) and repository path (-r) are required"
    show_help
fi

# Check if paths exist
if [ ! -f "$PACK_FILE" ]; then
    echo "Error: Pack file not found: $PACK_FILE"
    exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
    echo "Error: Repository path not found: $REPO_PATH"
    exit 1
fi

# Get the idx file for the pack
IDX_FILE="${PACK_FILE%.pack}.idx"

if [ ! -f "$IDX_FILE" ]; then
    echo "Error: Index file not found: $IDX_FILE"
    exit 1
fi

# Convert min size to bytes
MIN_SIZE_BYTES=$((MIN_SIZE_MB * 1024 * 1024))

echo "Analyzing pack file: $(basename "$PACK_FILE")"
echo "Repository path: $REPO_PATH"
echo "Minimum size: $MIN_SIZE_MB MB"
echo "Showing top $TOP_OBJECTS objects"
echo "----------------------------------------"

# Navigate to the repository - use sudo to ensure permissions
cd "$REPO_PATH" || { echo "Error: Cannot change to repository directory"; exit 1; }

# Extract large objects from the pack
echo "Extracting large objects from pack file..."

# Create a temporary file with proper permissions
TEMP_FILE=$(mktemp)
chmod 666 "$TEMP_FILE" 2>/dev/null

# Create a cache directory for batch mode if needed
CACHE_DIR=""
if [ "$BATCH_MODE" = true ]; then
    # Create a temporary directory for caching Git object metadata
    CACHE_DIR=$(mktemp -d /tmp/git-object-cache-XXXXXX)
    echo "Batch mode enabled. Using cache directory: $CACHE_DIR"
    
    # Ensure cache directory is cleaned up on exit
    trap 'rm -rf "$CACHE_DIR"' EXIT
fi

# Helper function to run commands with timeout
run_with_timeout() {
    local cmd="$1"
    local timeout_seconds="$2"
    
    # Use timeout command to prevent hanging on problematic repositories
    timeout "$timeout_seconds" bash -c "$cmd" || echo "Command timed out after $timeout_seconds seconds"
}

# Function to extract object sizes more efficiently for batch mode
extract_object_sizes() {
    local idx_file="$1"
    local top_n="$2"
    local output_file="$3"
    
    if [ "$BATCH_MODE" = true ] && [ -n "$CACHE_DIR" ]; then
        # In batch mode, we store the full object list once and reuse it
        local repo_hash=$(echo "$REPO_PATH" | sha256sum | cut -d ' ' -f1)
        local cache_file="${CACHE_DIR}/objects-${repo_hash}.txt"
        
        if [ ! -f "$cache_file" ]; then
            echo "Creating object cache for repository..."
            run_with_timeout "sudo git verify-pack -v '$idx_file' 2>/dev/null | sort -k 3 -n -r > '$cache_file'" "$TIMEOUT_SECONDS"
        fi
        
        # Use the cached file to extract top objects
        head -n "$top_n" "$cache_file" > "$output_file"
    else
        # Standard mode - process directly
        run_with_timeout "sudo git verify-pack -v '$idx_file' 2>/dev/null | sort -k 3 -n -r | head -n '$top_n' > '$output_file'" "$TIMEOUT_SECONDS"
    fi
}

# Get object sizes from the pack and filter by size - using sudo for Git operations
# Check repository size first to adjust how many objects to extract
repo_size=$(sudo du -s "$REPO_PATH" 2>/dev/null | awk '{print $1}')
actual_top_objects="$TOP_OBJECTS"

# Enhanced adaptive TOP_OBJECTS based on repository size
# This helps optimize performance for large repositories while providing sufficient detail
if [ "$repo_size" -gt 2000000 ]; then  # >2GB - extremely large repo
    echo "Extremely large repository detected ($repo_size KB). Limiting to top 2 objects for performance."
    actual_top_objects=2
elif [ "$repo_size" -gt 1000000 ]; then  # >1GB - very large repo
    echo "Very large repository detected ($repo_size KB). Limiting to top 3 objects for performance."
    actual_top_objects=3
elif [ "$repo_size" -gt 500000 ]; then  # >500MB - large repo
    echo "Large repository detected ($repo_size KB). Limiting to top 5 objects for performance."
    actual_top_objects=5
elif [ "$repo_size" -gt 250000 ]; then  # >250MB - medium-large repo
    echo "Medium-large repository detected ($repo_size KB). Limiting to top 7 objects for performance."
    actual_top_objects=7
elif [ "$repo_size" -gt 100000 ]; then  # >100MB - medium repo
    if [ "$TOP_OBJECTS" -gt 10 ]; then
        actual_top_objects=10  # Limit to 10 for medium repos
        echo "Medium repository detected ($repo_size KB). Limiting to top 10 objects for performance."
    else
        echo "Medium repository detected ($repo_size KB). Extracting top $TOP_OBJECTS objects."
    fi
else
    echo "Extracting top $TOP_OBJECTS objects (this may take a moment)..."
fi

# Get just the largest objects, and do it all at once to minimize Git operations
extract_object_sizes "$IDX_FILE" "$actual_top_objects" "/tmp/large_objects.$$"

# If we need to resolve filenames, do it more efficiently by getting all objects at once
# rather than calling git commands repeatedly
if [ -s /tmp/large_objects.$$ ]; then
    HASH_LIST=$(awk '{print $1}' /tmp/large_objects.$$)
    
    # Use a single call to rev-list rather than calling it for each hash
    if [ -n "$HASH_LIST" ]; then
        # Only do this for the first few largest objects to avoid lengthy operations
        # Get a subset of object mappings for performance
        echo "Getting object names for the largest objects..."
        sudo git rev-list --objects --all | grep -f <(echo "$HASH_LIST" | head -20) > /tmp/file_mappings.$$ 2>/dev/null
    fi
    
    # Now process each object
    while read -r hash type size rest; do
        if [ -n "$size" ] && [ "$size" -ge "$MIN_SIZE_BYTES" ]; then
            size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc)
            
            # Try to find the filename from our pre-fetched mappings
            if [ -f /tmp/file_mappings.$$ ]; then
                filename=$(grep "^$hash" /tmp/file_mappings.$$ | awk '{print $2}')
            else
                filename=""
            fi
            
            if [ -n "$filename" ]; then
                echo "$hash $size_mb MB $filename" >> "$TEMP_FILE"
            else
                # Just get the type without trying to resolve the full name
                obj_type=$(sudo git cat-file -t "$hash" 2>/dev/null || echo "unknown")
                echo "$hash $size_mb MB [${obj_type} object]" >> "$TEMP_FILE"
            fi
        fi
    done < /tmp/large_objects.$$
    
    # Clean up temporary files
    rm -f /tmp/large_objects.$$ /tmp/file_mappings.$$ 2>/dev/null
else
    echo "No large objects found in pack."
fi

# Display results
echo ""
echo "Large objects in pack file (sorted by size):"
echo "----------------------------------------"
echo "SHA-1                                      Size      Filename"
echo "----------------------------------------"
if [ -s "$TEMP_FILE" ]; then
    sort -k 2 -n -r "$TEMP_FILE" | while read -r hash size_mb filename; do
        printf "%-40s %-9s %s\n" "$hash" "$size_mb" "$filename"
    done
else
    echo "No large objects found or unable to access repository data."
    echo "Try running the script with sudo or checking repository permissions."
    
    # Check if the pack file actually exists and is readable
    if sudo test -f "$PACK_FILE"; then
        echo ""
        echo "Pack file information:"
        sudo ls -lah "$PACK_FILE"
        
        # Check corresponding idx file
        if sudo test -f "$IDX_FILE"; then
            echo ""
            echo "Index file information:"
            sudo ls -lah "$IDX_FILE"
        fi
    fi
fi

# Clean up
rm -f "$TEMP_FILE" 2>/dev/null

echo "----------------------------------------"
echo "Note: If some objects are shown as '[unknown]', '[detached object]', or '[unresolved object]',"
echo "they might be deleted in the latest commit but still present in history,"
echo "or they could be large blobs that are part of larger files."
echo ""
echo "To further investigate, you can use: sudo git -C \"$REPO_PATH\" log --all --find-object=<hash>"
