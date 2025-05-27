#!/bin/bash
# Test case for the special /nw/ formatted repository paths in file_info section
# This specific test focuses on the case where using process-packs-report.sh directly
# resulted in an empty output file

# Create a test input file with compressed repository path
TEST_INPUT="/tmp/test_direct_nw.txt"
cat > "$TEST_INPUT" << EOF
github/codeql-action:/data/user/repositories/6/nw/6f/49/22/18/18.git/objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack (80.22MB)
EOF

# Run the script with verbose output
echo "Running process-packs-report.sh with test input in verbose mode..."
SCRIPT_DIR="$(dirname "$0")"
bash "${SCRIPT_DIR}/process-packs-report.sh" -f "$TEST_INPUT" -v

# Check if the output file contains any data
OUTPUT_FILE="${TEST_INPUT%.txt}_resolved.txt"
OUTPUT_SIZE=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")

echo ""
echo "Test result:"
if [ "$OUTPUT_SIZE" -gt 10 ]; then
    echo "SUCCESS: Output file has content ($OUTPUT_SIZE lines)"
    echo "First 20 lines of output:"
    head -20 "$OUTPUT_FILE"
else
    echo "FAILED: Output file contains very little data ($OUTPUT_SIZE lines)"
    echo "Content of output file:"
    cat "$OUTPUT_FILE"
fi

echo ""
echo "Test complete. Temporary files:"
echo "- Input: $TEST_INPUT"
echo "- Output: $OUTPUT_FILE"
