#!/bin/bash
#
# Diagnostic script to verify local vs remote file mismatch
#

echo "======================================"
echo "CODA Config File Location Diagnostic"
echo "======================================"
echo ""

CONFIG_FILE="/home/ejfat/coda-vg/coda_scripts/../config/vme_test2.cnf"
CANONICAL_PATH=$(realpath /home/ejfat/coda-vg/coda_scripts/../config 2>/dev/null || echo "N/A")

echo "=== LOCAL MACHINE ==="
echo "Hostname: $(hostname)"
echo "Config path: $CONFIG_FILE"
echo "Canonical path: $CANONICAL_PATH"
echo "File exists: $([ -f "$CONFIG_FILE" ] && echo YES || echo NO)"
if [ -f "$CONFIG_FILE" ]; then
    echo "File size: $(stat -c %s "$CONFIG_FILE" 2>/dev/null || stat -f %z "$CONFIG_FILE" 2>/dev/null) bytes"
    echo "Last modified: $(stat -c %y "$CONFIG_FILE" 2>/dev/null || stat -f %Sm "$CONFIG_FILE" 2>/dev/null)"
    echo "Permissions: $(ls -l "$CONFIG_FILE")"
fi
echo ""

echo "=== REMOTE MACHINE (test2) ==="
ssh test2 << 'REMOTE_EOF'
CONFIG_FILE="/home/ejfat/coda-vg/coda_scripts/../config/vme_test2.cnf"
CANONICAL_PATH=$(realpath /home/ejfat/coda-vg/coda_scripts/../config 2>/dev/null || echo "N/A")

echo "Hostname: $(hostname)"
echo "Config path: $CONFIG_FILE"
echo "Canonical path: $CANONICAL_PATH"
echo "File exists: $([ -f "$CONFIG_FILE" ] && echo YES || echo NO)"
if [ -f "$CONFIG_FILE" ]; then
    echo "File size: $(stat -c %s "$CONFIG_FILE" 2>/dev/null || stat -f %z "$CONFIG_FILE" 2>/dev/null) bytes"
    echo "Last modified: $(stat -c %y "$CONFIG_FILE" 2>/dev/null || stat -f %Sm "$CONFIG_FILE" 2>/dev/null)"
    echo "Permissions: $(ls -l "$CONFIG_FILE")"
fi
REMOTE_EOF
echo ""

echo "=== FILESYSTEM CHECK ==="
echo "Local mount:"
mount | grep /home/ejfat || echo "(No /home/ejfat mount found)"
echo ""
echo "Remote mount:"
ssh test2 'mount | grep /home/ejfat' || echo "(No /home/ejfat mount found)"
echo ""

echo "=== DEVICE IDS (for NFS detection) ==="
echo "Local device ID: $(stat -c "%d" /home/ejfat/coda-vg 2>/dev/null || stat -f %d /home/ejfat/coda-vg 2>/dev/null)"
echo "Remote device ID: $(ssh test2 'stat -c "%d" /home/ejfat/coda-vg 2>/dev/null || stat -f %d /home/ejfat/coda-vg 2>/dev/null')"
echo ""
echo "If device IDs differ, filesystems are NOT shared"
echo "If device IDs match, filesystems MAY be NFS-shared"
echo ""

echo "=== CONCLUSION ==="
if [ -f "$CONFIG_FILE" ]; then
    echo "✓ Config file EXISTS locally"
else
    echo "✗ Config file MISSING locally"
fi

if ssh test2 "[ -f $CONFIG_FILE ]"; then
    echo "✓ Config file EXISTS remotely"
else
    echo "✗ Config file MISSING remotely ← THIS IS THE PROBLEM!"
fi
