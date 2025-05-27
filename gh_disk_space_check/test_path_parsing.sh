#!/bin/bash
# Quick test of path extraction logic from process-packs-report.sh
# This focuses on the parsing of lines, not the full script execution

echo "Testing repository path extraction from file_info containing /nw/ format paths..."

test_extract() {
  local line="$1"
  echo -e "\nInput line: $line"
  
  # Split the line at the colon for repo_name and file_info (same as in process-packs-report.sh)
  repo_name=$(echo "$line" | cut -d':' -f1 | xargs)
  file_info=$(echo "$line" | cut -d':' -f2- | xargs)
  
  echo "Initial parsing:"
  echo "  repo_name: $repo_name"
  echo "  file_info: $file_info"
  
  # Check for special case where the repository path is in file_info rather than repo_name
  if [[ "$file_info" == "/data/user/repositories/"*"/nw/"*"/objects/pack/"* ]]; then
    echo "  → Detected /nw/ format in file_info"
    
    # Extract the repository path from file_info using pattern matching
    if [[ "$file_info" =~ (/data/user/repositories/[^/]+/nw/[^/]+/[^/]+/[^/]+/[^/]+/[^/]+\.git) ]]; then
      actual_repo_path=${BASH_REMATCH[1]}
      # Store the original repo_name
      original_repo_name="$repo_name"
      # Set the repo_name to the actual repository path
      repo_name="$actual_repo_path"
      # Update file_info to contain only the objects/pack part
      file_info="${file_info#*$actual_repo_path/}"
      
      echo "  After special case handling:"
      echo "    original_repo_name: $original_repo_name"
      echo "    repo_name (corrected): $repo_name"
      echo "    file_info (corrected): $file_info"
    else
      echo "  → Pattern match failed"
    fi
  else
    echo "  → Standard format (no special handling needed)"
  fi
  
  # Extract pack file from file_info
  if [[ "$file_info" =~ (objects/pack/pack-[^[:space:]]+\.pack) ]]; then
    pack_file=${BASH_REMATCH[1]}
    echo "  Extracted pack_file: $pack_file"
  fi
}

# Test cases
echo "=== Test Case 1: Standard format ==="
test_extract "standard-repo:/data/user/repositories/standard/repo.git/objects/pack/pack-fedcba654321.pack (75MB)"

echo -e "\n=== Test Case 2: Compressed /nw/ format ==="
test_extract "github/codeql-action:/data/user/repositories/6/nw/6f/49/22/18/18.git/objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack (80.22MB)"

echo -e "\n=== Test Case 3: Another /nw/ format ==="
test_extract "another-repo:/data/user/repositories/a/nw/a8/7f/f6/4/4.git/objects/pack/pack-abcdef123456.pack (50MB)"
