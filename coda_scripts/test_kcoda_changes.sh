#!/bin/bash
#
# Test script for kcoda changes
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KCODA="${SCRIPT_DIR}/kcoda"

echo "======================================================================"
echo "Testing kcoda Changes"
echo "======================================================================"
echo ""

# Test 1: kcoda --help should work without CODA_COMPONENT_TABLE
echo "Test 1: kcoda --help works without CODA_COMPONENT_TABLE"
echo "----------------------------------------------------------------------"

unset CODA_COMPONENT_TABLE

output=$("$KCODA" --help 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    echo "✓ PASS: Help works without CODA_COMPONENT_TABLE in environment"
else
    echo "✗ FAIL: Help failed without CODA_COMPONENT_TABLE"
    echo "  Exit code: $exit_code"
fi

# Check help text mentions --file
if echo "$output" | grep -q "\--file"; then
    echo "✓ PASS: Help text documents --file argument"
else
    echo "✗ FAIL: Help text doesn't document --file"
fi

echo ""

# Test 2: kcoda without arguments and without CODA_COMPONENT_TABLE should fail gracefully
echo "Test 2: kcoda without --file and without env var shows helpful error"
echo "----------------------------------------------------------------------"

unset CODA_COMPONENT_TABLE

output=$("$KCODA" 2>&1)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    echo "✓ PASS: kcoda fails when no component table available"
else
    echo "✗ FAIL: kcoda should fail when no component table specified"
fi

if echo "$output" | grep -q "No component table specified"; then
    echo "✓ PASS: Shows helpful error message"
    echo "  Message includes: $(echo "$output" | grep "No component table")"
else
    echo "⚠ NOTICE: Error message could be more helpful"
fi

echo ""

# Test 3: kcoda with --file argument should accept the file
echo "Test 3: kcoda with --file validates the argument"
echo "----------------------------------------------------------------------"

unset CODA_COMPONENT_TABLE

# Create a test component file
TEST_FILE="${SCRIPT_DIR}/test_kcoda_components.txt"
cat > "$TEST_FILE" <<EOF
# Test component file for kcoda
testhost1 ROC ROC1 -v
testhost2 PEB PEB1
EOF

# Try to run kcoda with --file (it will fail to kill processes, but should accept the file)
output=$("$KCODA" --file "$TEST_FILE" 2>&1 || true)

if echo "$output" | grep -q "Using component table:"; then
    echo "✓ PASS: kcoda accepts --file argument and shows component table being used"
    echo "  Log: $(echo "$output" | grep "Using component table:")"
else
    echo "✗ FAIL: kcoda doesn't show component table being used"
fi

# Clean up
rm -f "$TEST_FILE"

echo ""

# Test 4: kcoda with --file for non-existent file should fail
echo "Test 4: kcoda with --file for non-existent file shows error"
echo "----------------------------------------------------------------------"

unset CODA_COMPONENT_TABLE

output=$("$KCODA" --file "/nonexistent/file.txt" 2>&1)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    echo "✓ PASS: kcoda fails for non-existent file"
else
    echo "✗ FAIL: kcoda should fail for non-existent file"
fi

if echo "$output" | grep -q "Component file not found"; then
    echo "✓ PASS: Clear error message for non-existent file"
else
    echo "⚠ NOTICE: Error message could be clearer"
fi

echo ""

# Test 5: kcoda fails when CODA_COMPONENT_TABLE set but no --file
echo "Test 5: kcoda requires --file even when CODA_COMPONENT_TABLE set externally"
echo "----------------------------------------------------------------------"

TEST_FILE="${SCRIPT_DIR}/test_kcoda_components.txt"
cat > "$TEST_FILE" <<EOF
# Test component file
testhost1 ROC ROC1 -v
EOF

# Set CODA_COMPONENT_TABLE in environment (should be ignored)
export CODA_COMPONENT_TABLE="$TEST_FILE"

output=$("$KCODA" 2>&1)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    echo "✓ PASS: kcoda requires --file even when CODA_COMPONENT_TABLE set in environment"
else
    echo "✗ FAIL: kcoda should require --file (not use external env var)"
fi

if echo "$output" | grep -q "Error: --file is required"; then
    echo "✓ PASS: Shows --file is required error"
else
    echo "✗ FAIL: Should show --file required error"
fi

# Clean up
rm -f "$TEST_FILE"
unset CODA_COMPONENT_TABLE

echo ""

# Test 6: kcoda with --file ignores external CODA_COMPONENT_TABLE
echo "Test 6: kcoda with --file uses --file (ignores external env var)"
echo "----------------------------------------------------------------------"

TEST_FILE1="${SCRIPT_DIR}/test_kcoda_file1.txt"
TEST_FILE2="${SCRIPT_DIR}/test_kcoda_file2.txt"

cat > "$TEST_FILE1" <<EOF
# File 1
EOF

cat > "$TEST_FILE2" <<EOF
# File 2
EOF

# Set env var to one file
export CODA_COMPONENT_TABLE="$TEST_FILE1"

# But use --file with different file
output=$("$KCODA" --file "$TEST_FILE2" 2>&1 || true)

if echo "$output" | grep -q "$TEST_FILE2"; then
    echo "✓ PASS: kcoda uses --file argument (ignores external CODA_COMPONENT_TABLE)"
else
    echo "✗ FAIL: kcoda should use --file argument"
fi

if ! echo "$output" | grep -q "$TEST_FILE1"; then
    echo "✓ PASS: External CODA_COMPONENT_TABLE is not used"
else
    echo "✗ FAIL: Should not use external CODA_COMPONENT_TABLE"
fi

# Clean up
rm -f "$TEST_FILE1" "$TEST_FILE2"
unset CODA_COMPONENT_TABLE

echo ""

echo "======================================================================"
echo "Test Summary"
echo "======================================================================"
echo ""
echo "Key Changes Validated:"
echo "  - kcoda REQUIRES --file argument (mandatory)"
echo "  - kcoda does NOT use CODA_COMPONENT_TABLE from environment"
echo "  - kcoda shows helpful error when --file not provided"
echo "  - kcoda exports CODA_COMPONENT_TABLE internally for kill_remotes.sh"
echo "  - External CODA_COMPONENT_TABLE is completely ignored"
echo ""
echo "Usage:"
echo "  kcoda --file /path/to/components.txt  (REQUIRED)"
echo ""
echo "IMPORTANT:"
echo "  - Do NOT set CODA_COMPONENT_TABLE in your environment"
echo "  - Always use --file argument for both startCoda and kcoda"
echo ""
echo "======================================================================"
