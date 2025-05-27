# Repository Analysis Script Fixes

## Issues Fixed

1. Added support for compressed repository paths with `/nw/` format used in GitHub Enterprise Server
   - Format example: `/data/user/repositories/a/nw/a8/7f/f6/4/4.git`

2. Fixed `clean_repo_path` function in `process-packs-report.sh` to correctly handle these paths
   - Special case detection for `/nw/` path segments
   - Better handling of potential duplicate path components

3. Added a new `extract_repo_name` function to `repo-filesize-analysis.sh` to properly convert paths to repository names
   - Ensures compressed paths are correctly preserved (including `/nw/` part)
   - Avoids stripping necessary path segments

4. Updated all repository name extraction points to use the new `extract_repo_name` function
   - Consistent handling across different parts of the script
   - Better reliability with both standard and compressed repository paths

5. Improved safety of repository name resolution
   - Line-by-line processing with safer string manipulation methods
   - Avoids sed errors that can occur with special characters in paths
   - Handles various edge cases better

6. Fixed handling of repository paths in the file_info section (May 26, 2025 update)
   - Added special detection for input lines like `github/codeql-action:/data/user/repositories/6/nw/6f/49/22/18/18.git/objects/pack/...`
   - Correctly identifies and extracts repository paths from file_info when they use the `/nw/` format
   - Properly separates pack file names from repository paths in file_info
   - Fixes empty output files that were occurring due to path resolution failures

7. Fixed syntax errors in script (May 26, 2025 update)
   - Resolved corrupted file header that was causing syntax errors
   - Properly separated header comments from code section
   - Ensured script runs without syntax errors

8. Improved size extraction (May 26, 2025 update)
   - Enhanced regex pattern to handle decimal numbers in sizes (e.g., `80.22MB`)
   - Added fallback to extract size from full line if not found in file_info
   - Handles both space and non-space formats in size values

## Testing

### Basic Path Handling Tests
Run the `test_quick.sh` script to verify that both compressed and standard repository paths are correctly processed.
The script demonstrates:

1. Path resolution for standard repository paths
2. Path resolution for compressed `/nw/` format repository paths 
3. Proper repository name extraction in both cases
4. Correct handling of edge cases and potential duplicated path components

### Advanced Path Parsing Tests
Run the `test_path_parsing.sh` script to test the path extraction logic specifically for the problematic input format where repository paths are in the file_info section. This tests the key fixes made on May 26, 2025.

### Full Integration Test
Run the `test_nw_format.sh` script to perform a full integration test with sample input data that includes compressed `/nw/` paths in the file_info section. This verifies that the updated script correctly processes these special path formats.

## How to Verify

1. Run `repo-filesize-analysis.sh` on a server with repositories using the compressed path format
2. Verify that the output files contain correct repository names
3. Run `process-packs-report.sh` on the output files and check that pack files are correctly resolved

If using a test environment, you can verify with:
```bash
./repo-filesize-analysis.sh -r -m 10 -M 100 -x 10
```

This will run the script with object resolution enabled, looking for files between 10MB and 100MB in size, analyzing the top 10 repositories.
