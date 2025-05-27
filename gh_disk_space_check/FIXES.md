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

## Testing

Run the `test_quick.sh` script to verify that both compressed and standard repository paths are correctly processed.
The script demonstrates:

1. Path resolution for standard repository paths
2. Path resolution for compressed `/nw/` format repository paths 
3. Proper repository name extraction in both cases
4. Correct handling of edge cases and potential duplicated path components

## How to Verify

1. Run `repo-filesize-analysis.sh` on a server with repositories using the compressed path format
2. Verify that the output files contain correct repository names
3. Run `process-packs-report.sh` on the output files and check that pack files are correctly resolved

If using a test environment, you can verify with:
```bash
./repo-filesize-analysis.sh -r -m 10 -M 100 -x 10
```

This will run the script with object resolution enabled, looking for files between 10MB and 100MB in size, analyzing the top 10 repositories.
