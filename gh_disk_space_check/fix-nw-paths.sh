#!/bin/bash
# Simplified script to handle the /nw/ format repository paths
# This script focuses solely on the specific issue with /nw/ paths and is
# designed to be a reliable fallback if the main script has issues

INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <input_file>"
    echo "Example: $0 /tmp/repos_over_5mb.txt"
    exit 1
fi

OUTPUT_FILE="${INPUT_FILE%.txt}_resolved.txt"
echo "Processing input file: $INPUT_FILE"
echo "Output will be written to: $OUTPUT_FILE"

# Clear the output file
> "$OUTPUT_FILE"

echo "Scanning for /nw/ format repository paths..."
COUNT=0

while IFS= read -r line; do
    # Look for the /nw/ format pattern
    if [[ "$line" =~ (/data/user/repositories/[^/]+/nw/[^/]+/[^/]+/[^/]+/[^/]+/[^/]+\.git)/objects/pack/(pack-[^[:space:]]+\.pack) ]]; then
        # Extract components
        repo_path="${BASH_REMATCH[1]}"
        pack_file="${BASH_REMATCH[2]}"
        
        # Try to extract size information
        if [[ "$line" =~ \(([0-9.]+)[[:space:]]*([A-Za-z]+)\) ]]; then
            size="${BASH_REMATCH[1]}"
            unit="${BASH_REMATCH[2]}"
        else
            size="unknown"
            unit="size"
        fi
        
        COUNT=$((COUNT+1))
        echo "[$COUNT] Processing: $repo_path - $pack_file ($size$unit)"
        
        # Write formatted output to the output file
        echo "==== Repository: $repo_path ====" >> "$OUTPUT_FILE"
        echo "Pack file: objects/pack/$pack_file ($size$unit)" >> "$OUTPUT_FILE"
        echo "Repository path: $repo_path" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "NOTE: This is a compressed /nw/ format repository path." >> "$OUTPUT_FILE"
        echo "      Actual objects cannot be resolved without Git repository access." >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "Estimated pack file size: $size$unit" >> "$OUTPUT_FILE"
        echo "Repository format: compressed /nw/ path" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "----------------------------------------" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done < "$INPUT_FILE"

echo "Processing complete!"
echo "Found $COUNT repositories with /nw/ format paths."

if [ $COUNT -eq 0 ]; then
    echo "WARNING: No /nw/ format paths found in the input file."
    echo "Example format: github/codeql-action:/data/user/repositories/6/nw/6f/49/22/18/18.git/objects/pack/pack-3c10048ee49d193b3bde170157dca8e4933e9cb3.pack (80.22MB)"
else
    echo "Output written to: $OUTPUT_FILE"
    echo "First 10 lines of output:"
    head -10 "$OUTPUT_FILE"
fi
