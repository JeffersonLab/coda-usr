#!/bin/bash
#
# Test script to demonstrate waiting for peds file to be closed
#

TEST_PEDS_FILE="/tmp/test_simulated.peds"

# Simulate slow file writing in background
simulate_slow_write() {
    local file=$1
    echo "Simulating slow write to $file..."
    rm -f "$file"

    # Write file slowly over 5 seconds
    echo "FADC250_CRATE test2" > "$file"
    sleep 1
    echo "FADC250_SLOT 3" >> "$file"
    sleep 1
    echo "FADC250_ALLCH_PED  159.171  149.630  158.221  149.961  147.498  105.140  162.479  145.465  120.902  147.148  147.477  144.218  121.521  144.166  117.929  146.181" >> "$file"
    sleep 1
    echo "FADC250_SLOT 4" >> "$file"
    sleep 1
    echo "FADC250_ALLCH_PED  105.148  118.741  176.517  117.695  163.911  145.115  153.443  113.491  173.660  143.411  107.573  107.231  119.075  125.699   96.842  134.597" >> "$file"
    sleep 1
    echo "FADC250_CRATE end" >> "$file"
    echo "Simulation complete - file closed"
}

# Start background writer
simulate_slow_write "$TEST_PEDS_FILE" &
WRITER_PID=$!

echo "======================================"
echo "Testing wait for peds file logic"
echo "======================================"
echo ""

# Wait logic (same as in startCoda)
PEDS_FILE="$TEST_PEDS_FILE"
wait_count=0
max_wait=60

# First, wait for file to exist
echo "Waiting for pedestal file: $PEDS_FILE"
while [[ ! -f "$PEDS_FILE" && $wait_count -lt $max_wait ]]; do
    sleep 1
    wait_count=$((wait_count + 1))
done

if [[ ! -f "$PEDS_FILE" ]]; then
    echo "ERROR: Pedestal file not found after ${max_wait}s"
    exit 1
fi

# File exists, now wait for it to be closed (size stabilizes)
echo "Pedestal file found, waiting for write completion..."
prev_size=-1
stable_count=0
while [[ $wait_count -lt $max_wait && $stable_count -lt 3 ]]; do
    curr_size=$(wc -c < "$PEDS_FILE" 2>/dev/null || echo 0)

    echo "  Check: size=$curr_size bytes, prev=$prev_size, stable=$stable_count/3"

    if [[ $curr_size -eq $prev_size && $curr_size -gt 0 ]]; then
        # Size unchanged and non-zero, increment stable counter
        stable_count=$((stable_count + 1))
    else
        # Size changed, reset stable counter
        stable_count=0
    fi

    prev_size=$curr_size

    if [[ $stable_count -lt 3 ]]; then
        sleep 1
        wait_count=$((wait_count + 1))
    fi
done

if [[ $stable_count -lt 3 ]]; then
    echo "WARNING: File may still be writing"
else
    echo "SUCCESS: File ready (${prev_size} bytes, waited ${wait_count}s total)"
fi

echo ""
echo "Final file contents:"
cat "$PEDS_FILE"

# Cleanup
wait $WRITER_PID
rm -f "$PEDS_FILE"
