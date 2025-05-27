#!/bin/bash
# Test script to verify our fixes for compressed repository paths

# Test repository paths
PATHS=(
  "/data/user/repositories/a/nw/a8/7f/f6/4/4.git"
  "/data/user/repositories/b/nw/10/a2/3f/5/1.git"
  "/data/user/repositories/foo/bar/baz.git"
  "/data/user/repositories/organization/repo.git"
)

# Source the clean_repo_path function from process-packs-report.sh
source /home/mj420/Desktop/TOR/MEMORY_CORE/Logs/2025/git/YNOT/ynot/gh_disk_space_check/process-packs-report.sh

echo "Testing clean_repo_path function:"
echo "================================="
for path in "${PATHS[@]}"; do
  cleaned=$(clean_repo_path "$path")
  echo "Original: $path"
  echo "Cleaned:  $cleaned"
  echo ""
done

# Test extract_repo_name function from repo-filesize-analysis.sh
source /home/mj420/Desktop/TOR/MEMORY_CORE/Logs/2025/git/YNOT/ynot/gh_disk_space_check/repo-filesize-analysis.sh

echo "Testing extract_repo_name function:"
echo "=================================="
for path in "${PATHS[@]}"; do
  extracted=$(extract_repo_name "$path")
  echo "Original: $path"
  echo "Extracted: $extracted"
  echo ""
done

# Test problematic double repository cases
DOUBLE_PATHS=(
  "/data/user/repositories/foo/bar/baz.git"
  "/data/user/repositories//data/user/repositories/foo/bar/baz.git"
  "/data/user/repositories/a/nw/a8/7f/f6/4/4.git"
  "/data/user/repositories//data/user/repositories/a/nw/a8/7f/f6/4/4.git"
)

echo "Testing double repository path handling:"
echo "======================================"
for path in "${DOUBLE_PATHS[@]}"; do
  cleaned=$(clean_repo_path "$path")
  echo "Original: $path"
  echo "Cleaned:  $cleaned"
  echo ""
done

# Check if a file with duplicate paths works correctly
echo "Testing output file replacement:"
echo "==============================="

# Create a test output file with repository paths
TEST_OUTPUT="/tmp/test_output.txt"
cat > "$TEST_OUTPUT" << EOF
/data/user/repositories/a/nw/a8/7f/f6/4/4.git:objects/pack/pack-abcdef123456.pack (50MB)
/data/user/repositories/b/nw/10/a2/3f/5/1.git:objects/pack/pack-fedcba654321.pack (75MB)
/data/user/repositories/organization/repo.git:objects/pack/pack-123456abcdef.pack (100MB)
EOF

# Process the file manually with awk for path replacement
echo "File content before processing:"
cat "$TEST_OUTPUT"

echo -e "\nProcessing test output file..."
for path in "${PATHS[@]}"; do
  # Extract repository name using extract_repo_name function
  repo_name=$(extract_repo_name "$path")
  echo "Converting: $path -> $repo_name"
done

# Clean up
rm -f "$TEST_OUTPUT"
