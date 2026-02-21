#!/bin/bash
#
# Test script to validate component file parsing
#

COMPONENT_FILE="${1:-test_components.txt}"

# Resolve environment variables in the file path
resolve_path() {
    local path="$1"
    eval echo "$path"
}

RESOLVED_FILE=$(resolve_path "$COMPONENT_FILE")

echo "Testing file: $RESOLVED_FILE"
echo "==========================================="

# Check if file exists
if [[ ! -f "$RESOLVED_FILE" ]]; then
    echo "ERROR: File not found: $RESOLVED_FILE"
    exit 1
fi

# Parse the file
line_number=0
component_count=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))

    # Remove leading/trailing whitespace
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip blank lines
    if [[ -z "$line" ]]; then
        echo "Line $line_number: [BLANK - SKIPPED]"
        continue
    fi

    # Skip comment lines
    if [[ "$line" =~ ^# ]]; then
        echo "Line $line_number: [COMMENT - SKIPPED] $line"
        continue
    fi

    # Parse the line into fields
    read -r hostname comp_type comp_name rest <<< "$line"

    # Validate minimum required fields
    if [[ -z "$hostname" || -z "$comp_type" || -z "$comp_name" ]]; then
        echo "Line $line_number: [WARNING - INVALID] $line"
        continue
    fi

    echo "Line $line_number: [OK] host=$hostname type=$comp_type name=$comp_name options='$rest'"
    component_count=$((component_count + 1))

done < "$RESOLVED_FILE"

echo "==========================================="
echo "Total valid components: $component_count"
