#!/bin/bash
# Debug version to identify why files aren't being found

SIZE_MIN_MB=${SIZE_MIN_MB:-1}
SIZE_MAX_MB=${SIZE_MAX_MB:-25}
MAX_REPOS=${MAX_REPOS:-15}
REPO_BASE=${REPO_BASE:-"/data/user/repositories"}

SIZE_MIN_BYTES=$((SIZE_MIN_MB * 1024 * 1024))
SIZE_MAX_BYTES=$((SIZE_MAX_MB * 1024 * 1024))

echo "DEBUG: SIZE_MIN_BYTES=$SIZE_MIN_BYTES"
echo "DEBUG: SIZE_MAX_BYTES=$SIZE_MAX_BYTES"

# Find a few repositories to test
mapfile -t test_repos < <(sudo find "$REPO_BASE" -name "*.git" -type d 2>/dev/null | head -3)

echo "DEBUG: Found ${#test_repos[@]} repositories to test"

for repo in "${test_repos[@]}"; do
    echo "DEBUG: Testing repository: $repo"
    
    # Test pack files
    pack_dir="$repo/objects/pack"
    if [[ -d "$pack_dir" ]]; then
        echo "DEBUG: Pack directory exists: $pack_dir"
        
        # Count pack files
        pack_count=$(sudo find "$pack_dir" -name "*.pack" -type f 2>/dev/null | wc -l)
        echo "DEBUG: Found $pack_count pack files"
        
        # Test a few pack files
        while IFS= read -r pack_file; do
            echo "DEBUG: Testing pack file: $pack_file"
            if sudo test -f "$pack_file"; then
                file_size=$(sudo stat -c '%s' "$pack_file" 2>/dev/null)
                echo "DEBUG: Pack file size: $file_size bytes"
                if (( file_size >= SIZE_MIN_BYTES )); then
                    echo "DEBUG: ✅ Pack file meets size criteria!"
                else
                    echo "DEBUG: ❌ Pack file too small"
                fi
            else
                echo "DEBUG: ❌ Pack file not accessible"
            fi
            break  # Only test first pack file
        done < <(sudo find "$pack_dir" -name "*.pack" -type f 2>/dev/null)
    else
        echo "DEBUG: No pack directory found"
    fi
    
    # Test other large files
    echo "DEBUG: Looking for other large files..."
    large_files=$(sudo find "$repo" -path "$pack_dir" -prune -o -type f -size "+${SIZE_MIN_MB}M" -print 2>/dev/null | head -5)
    if [[ -n "$large_files" ]]; then
        echo "DEBUG: Found large files:"
        echo "$large_files"
    else
        echo "DEBUG: No large files found with find command"
    fi
    
    echo "DEBUG: ---"
    break  # Only test first repository
done
