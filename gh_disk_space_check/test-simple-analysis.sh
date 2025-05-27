#!/bin/bash
# Test script for simple-repo-analysis.sh
# Creates mock repository structure for testing

TEST_BASE="/tmp/test_repositories"
SCRIPT_PATH="/home/mj420/Desktop/TOR/MEMORY_CORE/Logs/2025/git/YNOT/ynot/gh_disk_space_check/simple-repo-analysis.sh"

echo "Setting up test environment..."

# Clean up any existing test data
sudo rm -rf "$TEST_BASE" 2>/dev/null

# Create test repository structure
mkdir -p "$TEST_BASE"

# Create some test repositories
repos=(
    "github/dependabot-action.git"
    "actions/labeler.git"
    "org-a/chaos-repo-1748297529-2.git"
    "actions/stale.git"
    "actions/setup-python.git"
    "github/codeql-action.git"
    "a/nw/a8/7f/f6/4/4.git"
    "6/nw/6f/49/22/18/18.git"
)

for repo in "${repos[@]}"; do
    repo_path="$TEST_BASE/$repo"
    mkdir -p "$repo_path/objects/pack"
    
    # Create some test files of various sizes
    case "$repo" in
        "github/codeql-action.git")
            # Large pack file > 25MB
            dd if=/dev/zero of="$repo_path/objects/pack/pack-abc123.pack" bs=1M count=30 2>/dev/null
            ;;
        "actions/labeler.git")
            # Medium pack file 1-25MB range
            dd if=/dev/zero of="$repo_path/objects/pack/pack-def456.pack" bs=1M count=15 2>/dev/null
            ;;
        "github/dependabot-action.git")
            # Small pack file < 1MB
            dd if=/dev/zero of="$repo_path/objects/pack/pack-ghi789.pack" bs=1K count=500 2>/dev/null
            ;;
        "6/nw/6f/49/22/18/18.git")
            # Test compressed path format with large file
            dd if=/dev/zero of="$repo_path/objects/pack/pack-compressed.pack" bs=1M count=20 2>/dev/null
            ;;
        *)
            # Other repos get small files
            dd if=/dev/zero of="$repo_path/objects/pack/pack-small.pack" bs=1K count=100 2>/dev/null
            ;;
    esac
    
    # Add some other test files
    mkdir -p "$repo_path/refs"
    echo "test" > "$repo_path/HEAD"
    dd if=/dev/zero of="$repo_path/large_blob" bs=1M count=5 2>/dev/null
done

echo "Test environment created at: $TEST_BASE"
echo "Running simplified repository analysis..."
echo ""

# Run the script with test data
sudo REPO_BASE="$TEST_BASE" "$SCRIPT_PATH" --min-size 1 --max-size 25 --max-repos 10

echo ""
echo "Test completed. Check the output files:"
echo "- /tmp/repos_over_25mb.txt"
echo "- /tmp/repos_1mb_to_25mb.txt"

# Show the contents of the output files
echo ""
echo "=== Contents of /tmp/repos_over_25mb.txt ==="
cat /tmp/repos_over_25mb.txt 2>/dev/null || echo "(empty)"

echo ""
echo "=== Contents of /tmp/repos_1mb_to_25mb.txt ==="
cat /tmp/repos_1mb_to_25mb.txt 2>/dev/null || echo "(empty)"

# Clean up test data
echo ""
read -p "Clean up test data? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo rm -rf "$TEST_BASE"
    echo "Test data cleaned up."
fi
