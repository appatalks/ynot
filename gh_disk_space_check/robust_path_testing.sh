#!/bin/bash
# Robust test of path extraction logic from process-packs-report.sh
# This focuses on the parsing of lines, not the full script execution
# Version: May 26, 2025 - Enhanced to include validation checks

echo "Comprehensive testing of repository path extraction with /nw/ format paths..."
echo "This script validates the fixes implemented on May 26, 2025"
echo "--------------------------------------------------------------"

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

# Test cases with validation
test_with_validation() {
  local test_name="$1"
  local input="$2"
  local expected_repo_path="$3"
  local expected_pack_file="$4"
  
  echo -e "\n=== $test_name ==="
  test_extract "$input"
  
  # Use a separate function to extract the values for validation
  local result=$(test_extract_silent "$input")
  local extracted_repo_path=$(echo "$result" | grep "repo_name (corrected):" | awk -F ': ' '{print $2}' || echo "NOT_FOUND")
  local extracted_pack_file=$(echo "$result" | grep "Extracted pack_file:" | awk -F ': ' '{print $2}' || echo "NOT_FOUND")
  
  echo -e "\nValidation Results:"
  
  if [ "$extracted_repo_path" == "$expected_repo_path" ]; then
    echo "✓ Repository path correctly extracted: $extracted_repo_path"
  else
    echo "✗ Repository path extraction FAILED!"
    echo "  Expected: $expected_repo_path"
    echo "  Got:      $extracted_repo_path"
  fi
  
  if [ "$extracted_pack_file" == "$expected_pack_file" ]; then
    echo "✓ Pack file correctly extracted: $extracted_pack_file"
  else
    echo "✗ Pack file extraction FAILED!"
    echo "  Expected: $expected_pack_file"
    echo "  Got:      $extracted_pack_file"
  fi
}

# Silent version for validation
test_extract_silent() {
  local line="$1"
  
  # Split the line at the colon for repo_name and file_info (same as in process-packs-report.sh)
  repo_name=$(echo "$line" | cut -d':' -f1 | xargs)
  file_info=$(echo "$line" | cut -d':' -f2- | xargs)
  
  local output=""
  output+="Initial parsing:\n"
  output+="  repo_name: $repo_name\n"
  output+="  file_info: $file_info\n"
  
  # Check for special case where the repository path is in file_info rather than repo_name
  if [[ "$file_info" == "/data/user/repositories/"*"/nw/"*"/objects/pack/"* ]]; then
    output+="  → Detected /nw/ format in file_info\n"
    
    # Extract the repository path from file_info using pattern matching
    if [[ "$file_info" =~ (/data/user/repositories/[^/]+/nw/[^/]+/[^/]+/[^/]+/[^/]+/[^/]+\.git) ]]; then
      actual_repo_path=${BASH_REMATCH[1]}
      original_repo_name="$repo_name"
      repo_name="$actual_repo_path"
      file_info="${file_info#*$actual_repo_path/}"
      
      output+="  After special case handling:\n"
      output+="    original_repo_name: $original_repo_name\n"
      output+="    repo_name (corrected): $repo_name\n"
      output+="    file_info (corrected): $file_info\n"
    else
      output+="  → Pattern match failed\n"
    fi
  else
    output+="  → Standard format (no special handling needed)\n"
    output+="    repo_name (corrected): $repo_name\n"
  fi
  
  # Extract pack file from file_info
  if [[ "$file_info" =~ (objects/pack/pack-[^[:space:]]+\.pack) ]]; then
    pack_file=${BASH_REMATCH[1]}
    output+="  Extracted pack_file: $pack_file\n"
  fi
  
  echo -e "$output"
}

# Standard test cases
test_with_validation "Test Case 1: Standard format" \
  "standard-repo:/data/user/repositories/standard/repo.git/objects/pack/pack-fedcba654321.pack (75MB)" \
  "standard-repo" \
  "objects/pack/pack-fedcba654321.pack"

test_with_validation "Test Case 2: Compressed /nw/ format" \
  "github/codeql-action:/data/user/repositories/6/nw/6f/49/22/18/18.git/objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack (80.22MB)" \
  "/data/user/repositories/6/nw/6f/49/22/18/18.git" \
  "objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack"

test_with_validation "Test Case 3: Another /nw/ format" \
  "another-repo:/data/user/repositories/a/nw/a8/7f/f6/4/4.git/objects/pack/pack-abcdef123456.pack (50MB)" \
  "/data/user/repositories/a/nw/a8/7f/f6/4/4.git" \
  "objects/pack/pack-abcdef123456.pack"

# Additional test cases
test_with_validation "Test Case 4: Path with double /data/user/repositories prefix" \
  "github/actions:/data/user/repositories//data/user/repositories/c/nw/c3/b4/55/7/9.git/objects/pack/pack-1234567890abcdef.pack (120MB)" \
  "/data/user/repositories/c/nw/c3/b4/55/7/9.git" \
  "objects/pack/pack-1234567890abcdef.pack"

test_with_validation "Test Case 5: Decimal size without space" \
  "enterprise/app:/data/user/repositories/d/nw/d5/6f/78/8/9.git/objects/pack/pack-9876543210abcdef.pack (99.5MB)" \
  "/data/user/repositories/d/nw/d5/6f/78/8/9.git" \
  "objects/pack/pack-9876543210abcdef.pack"
