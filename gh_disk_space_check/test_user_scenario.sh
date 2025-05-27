#!/bin/bash
# Test script that replicates the user's exact command line scenario
# This tests the repo-filesize-analysis.sh integration with process-packs-report.sh
# specifically for the /nw/ format path case

# Create the test input file
echo "Creating test input file at /tmp/repos_over_5mb.txt..."
cat > /tmp/repos_over_5mb.txt << EOF
github/codeql-action:/data/user/repositories/6/nw/6f/49/22/18/18.git/objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack (80.22MB)
EOF

# Run the command that replicates the user's scenario
# For this test we'll use our local version of the process-packs-report.sh script
echo "Running process-packs-report.sh on /tmp/repos_over_5mb.txt..."
SCRIPT_DIR="$(dirname "$0")"

# Set variables similar to how repo-filesize-analysis.sh would set them
DISTINCT_REPOS_OVER=1
AUTO_ADJUST_TOP_OBJECTS=true
TOP_OBJECTS=10

# Run the command
echo "Using TOP_OBJECTS=$TOP_OBJECTS for execution"
"${SCRIPT_DIR}/process-packs-report.sh" -f /tmp/repos_over_5mb.txt -t $TOP_OBJECTS -v

# Check the output file
OUTPUT_FILE="/tmp/repos_over_5mb_resolved.txt"
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
