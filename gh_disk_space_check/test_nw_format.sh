#!/bin/bash
# Test script to verify that process-packs-report.sh correctly handles repository paths with /nw/ format
# This tests the special case where the repository path is inside the file_info section rather than the repo_name section

# Create a sample input file
TEST_INPUT="/tmp/test_nw_input.txt"
cat > "$TEST_INPUT" << EOF
github/codeql-action:/data/user/repositories/6/nw/6f/49/22/18/18.git/objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack (80.22MB)
another-repo:/data/user/repositories/a/nw/a8/7f/f6/4/4.git/objects/pack/pack-abcdef123456.pack (50MB)
standard-repo:/data/user/repositories/standard/repo.git/objects/pack/pack-fedcba654321.pack (75MB)
EOF

# Run the script in debug mode with verbose output
echo "Running process-packs-report.sh with test input..."
echo "Note: This test will show errors about repositories not being found, which is expected"
echo "The important part is to verify that the repository paths are correctly extracted"
echo ""

# Run the script with verbose output
SCRIPT_DIR="$(dirname "$0")"
bash "${SCRIPT_DIR}/process-packs-report.sh" -f "$TEST_INPUT" -v

# Extract and display the relevant parts from the output file
OUTPUT_FILE="${TEST_INPUT%.txt}_resolved.txt"

echo ""
echo "Checking repository paths in output file..."
grep -A 1 "Repository path:" "$OUTPUT_FILE" | head -10

# Clean up
echo ""
echo "Test complete. Temporary files:"
echo "- Input: $TEST_INPUT"
echo "- Output: $OUTPUT_FILE"
echo "You can examine these files manually for more details."
