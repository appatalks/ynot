#!/bin/bash
# Script to resolve Git pack objects to file paths

# Default values
PACK_FILE=""
REPO_PATH=""
MIN_SIZE_MB=1
SIZE_IN_BYTES=0
TOP_OBJECTS=10

# Help function
show_help() {
    echo "Usage: $0 -p <pack_file> -r <repository_path> [-m <min_size_MB>] [-t <top_objects>]"
    echo ""
    echo "Options:"
    echo "  -p  Full path to the pack file"
    echo "  -r  Path to the Git repository"
    echo "  -m  Minimum file size in MB to show (default: 1)"
    echo "  -t  Number of top objects to display (default: 10)"
    echo "  -h  Show this help"
    echo ""
    echo "Example:"
    echo "  $0 -p /data/user/repositories/org/repo.git/objects/pack/pack-abcd1234.pack -r /data/user/repositories/org/repo.git"
    exit 1
}

# Parse arguments
while getopts "p:r:m:t:h" opt; do
    case $opt in
        p) PACK_FILE="$OPTARG" ;;
        r) REPO_PATH="$OPTARG" ;;
        m) MIN_SIZE_MB="$OPTARG" ;;
        t) TOP_OBJECTS="$OPTARG" ;;
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

# Get object sizes from the pack and filter by size - using sudo for Git operations
echo "Extracting largest objects (this may take a moment)..."

# Get just the largest objects, and do it all at once to minimize Git operations
sudo git verify-pack -v "$IDX_FILE" 2>/dev/null | 
sort -k 3 -n -r | 
head -n "$TOP_OBJECTS" > /tmp/large_objects.$$

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
