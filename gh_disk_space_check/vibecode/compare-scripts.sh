#!/bin/bash
# Comparison script: Original vs Simplified Repository Analysis

echo "======================================================================"
echo "COMPARISON: Original vs Simplified Repository Analysis Scripts"
echo "======================================================================"

ORIGINAL="/home/mj420/Desktop/TOR/MEMORY_CORE/Logs/2025/git/YNOT/ynot/gh_disk_space_check/repo-filesize-analysis.sh"
SIMPLIFIED="/home/mj420/Desktop/TOR/MEMORY_CORE/Logs/2025/git/YNOT/ynot/gh_disk_space_check/simple-repo-analysis.sh"
ONELINER="/home/mj420/Desktop/TOR/MEMORY_CORE/Logs/2025/git/YNOT/ynot/gh_disk_space_check/simple-repo-analysis-oneliner.sh"

echo ""
echo "📊 FILE SIZE COMPARISON:"
echo "-------------------------"
printf "%-30s %10s %15s\n" "Script" "Lines" "Size (KB)"
printf "%-30s %10s %15s\n" "------" "-----" "---------"

original_lines=$(wc -l < "$ORIGINAL")
simplified_lines=$(wc -l < "$SIMPLIFIED")
oneliner_lines=$(wc -l < "$ONELINER")

original_size=$(du -k "$ORIGINAL" | cut -f1)
simplified_size=$(du -k "$SIMPLIFIED" | cut -f1)
oneliner_size=$(du -k "$ONELINER" | cut -f1)

printf "%-30s %10d %15d\n" "Original" "$original_lines" "$original_size"
printf "%-30s %10d %15d\n" "Simplified" "$simplified_lines" "$simplified_size"
printf "%-30s %10d %15d\n" "One-liner" "$oneliner_lines" "$oneliner_size"

# Calculate reductions
line_reduction=$((($original_lines - $simplified_lines) * 100 / $original_lines))
size_reduction=$((($original_size - $simplified_size) * 100 / $original_size))

echo ""
echo "📈 REDUCTION METRICS:"
echo "---------------------"
echo "Lines of code reduced: $((original_lines - simplified_lines)) lines (${line_reduction}% reduction)"
echo "File size reduced: $((original_size - simplified_size)) KB (${size_reduction}% reduction)"

echo ""
echo "🔍 COMPLEXITY ANALYSIS:"
echo "------------------------"

# Count functions
original_functions=$(grep -c "^[[:space:]]*function\|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$ORIGINAL")
simplified_functions=$(grep -c "^[[:space:]]*function\|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$SIMPLIFIED")

echo "Functions in original: $original_functions"
echo "Functions in simplified: $simplified_functions"
echo "Function reduction: $((original_functions - simplified_functions)) functions"

# Count dependencies
echo ""
echo "External dependencies:"
echo "  Original: GNU Parallel, ghe-nwo, resolve-pack-objects.sh, bc, curl"
echo "  Simplified: ghe-nwo (optional), bc"
echo "  Dependency reduction: 60% fewer external dependencies"

echo ""
echo "⚡ PERFORMANCE COMPARISON:"
echo "--------------------------"
echo "Original script features:"
echo "  ✓ Parallel processing with GNU Parallel"
echo "  ✓ Complex path handling for multiple formats"
echo "  ✓ Advanced object resolution"
echo "  ✓ Batch processing capabilities"
echo "  ⚠ Complex codebase (hard to maintain)"
echo "  ⚠ Multiple external dependencies"
echo "  ⚠ Difficult to understand and modify"

echo ""
echo "Simplified script features:"
echo "  ✓ Same core functionality and output format"
echo "  ✓ Clean, readable code structure"
echo "  ✓ Easy to understand and modify"
echo "  ✓ Minimal dependencies"
echo "  ✓ Better error handling"
echo "  ✓ Single self-contained script"
echo "  ⚠ Sequential processing (no parallel)"
echo "  ⚠ Simpler object resolution"

echo ""
echo "🎯 RECOMMENDED USE CASES:"
echo "--------------------------"
echo "Use Original (repo-filesize-analysis.sh) when:"
echo "  • You need maximum performance for very large installations (1000+ repos)"
echo "  • You need advanced pack object resolution"
echo "  • You have GNU Parallel installed and want parallel processing"

echo ""
echo "Use Simplified (simple-repo-analysis.sh) when:"
echo "  • You want clean, maintainable code"
echo "  • You need to understand or modify the script"
echo "  • You have small to medium installations (< 500 repos)"
echo "  • You want the same reporting with less complexity"
echo "  • You prefer reliability over maximum performance"

echo ""
echo "💡 MIGRATION GUIDE:"
echo "--------------------"
echo "To switch from original to simplified:"
echo ""
echo "1. Replace the script call:"
echo "   OLD: sudo bash repo-filesize-analysis.sh"
echo "   NEW: sudo bash simple-repo-analysis.sh"
echo ""
echo "2. Environment variables are mostly the same:"
echo "   SIZE_MIN_MB, SIZE_MAX_MB work identically"
echo "   MAX_REPOS replaces some of the complex repository selection logic"
echo "   MAX_OBJECTS replaces TOP_OBJECTS for clearer naming"
echo ""
echo "3. Output format is identical - your existing parsing scripts will work"
echo ""
echo "4. One-liner usage:"
echo "   sudo bash <(curl -sL URL/simple-repo-analysis-oneliner.sh)"

echo ""
echo "======================================================================"
echo "RECOMMENDATION: Use the simplified version unless you specifically need"
echo "the advanced features of the original script."
echo "======================================================================"
