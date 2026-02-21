#!/bin/bash
#
# Test script for configuration generation functions
#

# Source the functions from startCoda
source ./test_config_functions.sh

# Test parameters
TEST_HOSTNAME="test2"
BASE_FILE="../config/base.cnf"
PEDS_FILE="./test_example.peds"
OUTPUT_DIR="./test_output"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Testing configuration generation..."
echo "======================================"
echo ""

# Test 1: Extract VME section
echo "Test 1: Extracting VME section from base.cnf"
extract_vme_section "$BASE_FILE" "$OUTPUT_DIR/test_vme_section.txt"
echo "  Output: $OUTPUT_DIR/test_vme_section.txt"
echo "  Lines: $(wc -l < $OUTPUT_DIR/test_vme_section.txt)"
echo ""

# Test 2: Extract VTP section
echo "Test 2: Extracting VTP section from base.cnf"
extract_vtp_section "$BASE_FILE" "$OUTPUT_DIR/test_vtp_section.txt"
echo "  Output: $OUTPUT_DIR/test_vtp_section.txt"
echo "  Lines: $(wc -l < $OUTPUT_DIR/test_vtp_section.txt)"
echo ""

# Test 3: Get MAC/IP for hostname
echo "Test 3: Getting MAC/IP for hostname: $TEST_HOSTNAME"
mac_addr=""
ip_addr=""
get_mac_ip_from_base "$BASE_FILE" "$TEST_HOSTNAME" mac_addr ip_addr
echo "  MAC: $mac_addr"
echo "  IP: $ip_addr"
echo ""

# Test 4: Extract slots from peds file
echo "Test 4: Extracting slots from peds file"
slots=()
extract_slots_from_peds "$PEDS_FILE" slots
echo "  Slots found: ${slots[@]}"
echo ""

# Test 5: Compute VTP_PAYLOAD_EN
echo "Test 5: Computing VTP_PAYLOAD_EN from slots: ${slots[@]}"
payload_en=$(compute_vtp_payload_en "${slots[@]}")
echo "  VTP_PAYLOAD_EN: $payload_en"
echo ""

# Test 6: Generate vme config
echo "Test 6: Generating vme_${TEST_HOSTNAME}.cnf"
generate_vme_config "$TEST_HOSTNAME" "$BASE_FILE" "$PEDS_FILE" "$OUTPUT_DIR"
echo ""

# Test 7: Generate vtp config
echo "Test 7: Generating vtp_${TEST_HOSTNAME}.cnf"
generate_vtp_config "$TEST_HOSTNAME" "$BASE_FILE" "$PEDS_FILE" "$OUTPUT_DIR"
echo ""

echo "======================================"
echo "Test complete. Output files in: $OUTPUT_DIR"
echo ""
echo "Generated files:"
ls -lh "$OUTPUT_DIR"
