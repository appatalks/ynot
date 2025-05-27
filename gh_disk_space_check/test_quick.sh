#!/bin/bash
# Simpler test for compressed path handling

# Test repository paths
PATHS=(
  "/data/user/repositories/a/nw/a8/7f/f6/4/4.git"
  "/data/user/repositories/normal/repo.git"
)

# Function to extract repository name, handling special formats
extract_repo_name() {
    local repo_path="$1"
    local repo_name=""
    
    # Handle standard repository path format
    if [[ "$repo_path" == "/data/user/repositories/"* ]]; then
        repo_name=$(echo "$repo_path" | sed 's|/data/user/repositories/||g' | sed 's|\.git$||g')
        
        # Special handling for compressed repository paths with /nw/ format
        if [[ "$repo_name" == *"/nw/"* ]]; then
            # Keep the compressed format as is - it's a special case for GitHub Enterprise Server
            # Format correctly for display - but don't remove the /nw/ part
            repo_name=$(echo "$repo_name" | sed 's|/nw/|/nw/|g') # Preserve the /nw/ part
        fi
    else
        repo_name="$repo_path"
    fi
    
    echo "$repo_name"
}

# Clean repo path function
clean_repo_path() {
    local path="$1"
    local repo_base="/data/user/repositories"
    local original_path="$path"
    
    # First, normalize the path by removing trailing slashes
    path="${path%/}"
    
    # Special handling for compressed repository paths with /nw/ format
    if [[ "$path" == */nw/* ]]; then
        # Ensure the path is properly formatted for these compressed paths
        if [[ "$path" =~ (/data/user/repositories/[^/]+)/nw/ ]]; then
            local base_prefix="${BASH_REMATCH[1]}"
            local nw_part="${path#*$base_prefix/nw/}"
            path="$base_prefix/nw/$nw_part"
            
            # Verify we don't have duplicate /nw/ parts
            if [[ "$nw_part" == *"/nw/"* ]]; then
                path="$base_prefix/nw/${nw_part#*/nw/}"
            fi
        fi
    fi
    
    # Handle any double slash scenarios that might occur during replacements
    while [[ "$path" == *"//"* ]]; do
        path="${path//\/\//\/}"
    done
    
    echo "$path"
}

for path in "${PATHS[@]}"; do
  echo "Original: $path"
  echo "extract_repo_name: $(extract_repo_name "$path")" 
  echo "clean_repo_path:   $(clean_repo_path "$path")"
  echo ""
done
