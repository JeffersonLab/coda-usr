# VTP ROL - VTP Readout List for CODA

## Overview

This directory contains the VTP (VTP Trigger Processor) Readout List (ROL) for CODA 3.0. The ROL controls VTP hardware readout in streaming mode, including firmware loading, network configuration, and UDP statistics transmission.

## Files

- `vtp_sro_1udp.c` - Main VTP streaming readout list (single UDP connection)
- `VTP_source.h` - VTP-specific header with CODA macros
- `Makefile` - Build system for VTP ROL shared objects

## Configuration

### Config File Location

The VTP ROL reads configuration from per-host config files:

**File path:** `$CODA_CONFIG/vtp_<hostname>.cnf`

Where `<hostname>` is the VTP host with trailing "vtp" suffix stripped:
- `test2vtp` → uses `vtp_test2.cnf`
- `adccal1` → uses `vtp_adccal1.cnf`

**Alternative:** Use `rol->usrConfig` if defined by CODA run control.

### Required Configuration Keys

The following keys **MUST** be present in the config file:

#### Firmware Configuration (MANDATORY)

```bash
VTP_FIRMWARE_Z7  fe_vtp_z7_streamingv3_ejfat_v5.bin
VTP_FIRMWARE_V7  fe_vtp_v7_fadc_streamingv3_ejfat.bin
```

**Behavior if missing:**
```
ERROR: Z7 firmware filename not found in config file!
ERROR: Config must contain: VTP_FIRMWARE_Z7 <filename>
ERROR: Example: VTP_FIRMWARE_Z7 fe_vtp_z7_streamingv3_ejfat_v5.bin
```

VTP Download will **FAIL** if firmware keys are missing.

#### Network Configuration (MANDATORY)

```bash
VTP_NUM_CONNECTIONS  1              # Number of streaming connections (1-4)
VTP_NET_MODE         1              # 0=TCP, 1=UDP
VTP_LOCAL_PORT       10001          # Base local port
VTP_ENABLE_EJFAT     1              # Enable EJFAT headers (UDP only)
```

**Behavior if missing:**
```
ERROR: numConnections not set from config file!
ERROR: Config must contain VTP_NUM_CONNECTIONS or VTP_STREAMING_NSTREAMS > 0
```

VTP Prestart will **FAIL** if network config keys are missing.

#### Streaming Destination (MANDATORY)

```bash
VTP_STREAMING_DESTIP       129.57.177.28  # Destination IP address
VTP_STREAMING_DESTIPPORT   19522          # Destination port
```

### Optional Configuration Keys

#### VTP Statistics (Optional - Environment Variable Override Available)

```bash
VTP_STATS_HOST     129.57.29.231  # Stats receiver host (indra-s2)
VTP_STATS_PORT     19531           # Stats receiver port
VTP_STATS_INST     0               # Stats stream instance
VTP_SYNC_PKT_LEN   28              # Sync packet length in bytes
```

**Default values** (used if not in config):
- `VTP_STATS_HOST`: `129.57.29.231` (indra-s2 IP for forwarding sync packets)
- `VTP_STATS_PORT`: `19531`
- `VTP_STATS_INST`: `0`
- `VTP_SYNC_PKT_LEN`: `28` bytes

## Environment Variables

### VTP Statistics Override (Optional)

You can override the VTP statistics destination at runtime using environment variables:

```bash
export VTP_STATS_HOST="192.168.1.100"  # Override stats receiver host
export VTP_STATS_PORT="20000"          # Override stats receiver port
```

**Priority order:**
1. Environment variable (if set and non-empty)
2. Config file value (if present)
3. Hardcoded default

**Use case:** Temporarily redirect stats to a different receiver without modifying config files.

**Example:**
```bash
# Override stats destination for testing
export VTP_STATS_HOST="test-server.example.com"
export VTP_STATS_PORT="9999"

# Start CODA (VTP will send stats to test-server:9999)
startCoda --file components.txt

# Unset to restore default behavior
unset VTP_STATS_HOST
unset VTP_STATS_PORT
```

### CODA Environment Variables (Required)

```bash
export CODA=/site/coda/3.10_devel           # CODA installation directory
export CODA_CONFIG=/path/to/config          # Config/pedestal directory
export CODA_FIRMWARE=/path/to/firmware      # Firmware directory (optional, defaults to $CODA/firmware)
```

## Firmware Loading

Firmware files are loaded during the **Download** phase:

1. VTP ROL reads `VTP_FIRMWARE_Z7` and `VTP_FIRMWARE_V7` from config
2. Constructs full paths: `$CODA_FIRMWARE/<filename>`
3. Validates files exist and are readable
4. Loads Z7 firmware: `vtpZ7CfgLoad()`
5. Loads V7 firmware: `vtpV7CfgLoad()`

**Firmware directory priority:**
1. `$CODA_FIRMWARE` (if set)
2. `$CODA/firmware` (fallback)

## Build Instructions

### Prerequisites

- CODA 3.0 environment configured
- `$CODA` environment variable set
- VTP library (`libvtp.so`) installed in `$CODA/Linux-armv7l/lib`
- Cross-compiler for ARM architecture

### Build Commands

```bash
cd rol/vtp_rol

# Clean previous builds
make clean

# Build VTP ROL shared object
make vtp_sro_1udp.so
```

### Build Output

```
vtp_sro_1udp.so
```

This shared object is loaded by CODA run control during component Download.

## VTP Statistics UDP Sender

The VTP ROL includes a background thread that sends 1 Hz UDP statistics packets during runs.

### Statistics Packet Contents

Each packet contains:
- Source ID (ROCID)
- Frame count (64-bit extended)
- Event rate (computed from frame deltas)
- Timestamp (frame_number × 65.535 µs in nanoseconds)

### Configuration

**Via config file:**
```bash
VTP_STATS_HOST     129.57.29.231
VTP_STATS_PORT     19531
VTP_STATS_INST     0
VTP_SYNC_PKT_LEN   28
```

**Via environment variables (override):**
```bash
export VTP_STATS_HOST="your-stats-host"
export VTP_STATS_PORT="your-port"
```

### Lifecycle

- **Started:** During `rocGo()` (run start)
- **Runs:** Every 1 second in background thread
- **Stopped:** During `rocEnd()` (run end)

## Payload Configuration

VTP payload ports are configured via `VTP_PAYLOAD_EN` in the config file:

```bash
VTP_PAYLOAD_EN  0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0
```

**Format:** 16 space-separated values (0 or 1) for payloads 1-16

**Slot-to-Payload Mapping:**
```
Slot:     10  13   9  14   8  15   7  16   6  17   5  18   4  19   3  20
Payload:   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
```

**Note:** `vtpGetPayloadEnableArray()` is not available in the VTP library. The config file is the only way to configure payloads.

## Troubleshooting

### Undefined Symbol Errors

**Error:**
```
daLogMsg: ERROR: dlopen failed on rol: undefined symbol: vtpGetFirmwareV7
```

**Cause:** Old build using non-existent `vtpGet*()` functions

**Solution:**
```bash
cd rol/vtp_rol
git pull
make clean
make vtp_sro_1udp.so
```

### Firmware File Not Found

**Error:**
```
ERROR: Z7 firmware file not found or not readable: /path/to/firmware/file.bin
ERROR: Check CODA_FIRMWARE environment variable and firmware file
```

**Solution:**
1. Verify firmware file exists: `ls -l $CODA_FIRMWARE/fe_vtp_z7_streamingv3_ejfat_v5.bin`
2. Check `CODA_FIRMWARE` is set correctly
3. Verify file permissions (must be readable)
4. Confirm filename in config matches actual file

### Missing Config Keys

**Error:**
```
ERROR: VTP config file 'vtp_test2.cnf' not found or not readable
```

**Solution:**
1. Run `startCoda --file components.txt --config` to generate config files
2. Verify `$CODA_CONFIG` is set correctly
3. Check that `base.cnf` contains VTP configuration section
4. Ensure hostname mapping exists in `base.cnf`

### Stats Not Being Received

**Check:**
1. Verify stats receiver is running and listening
2. Check firewall rules allow UDP to destination port
3. Override stats destination for testing:
   ```bash
   export VTP_STATS_HOST="localhost"
   export VTP_STATS_PORT="9999"
   ```
4. Use `tcpdump` to verify packets are being sent:
   ```bash
   tcpdump -i any -n udp port 19531
   ```

## Known Limitations

### VTP Library Limitations

The following `vtpGet*()` functions **do not exist** in `libvtp.so`:

- `vtpGetFirmwareV7()` - **Fixed:** reads from config file
- `vtpGetFirmwareZ7()` - **Fixed:** reads from config file
- `vtpGetStatsHost()` - **Fixed:** uses default or env var
- `vtpGetStatsPort()` - **Fixed:** uses default or env var
- `vtpGetStatsInst()` - **Fixed:** uses default (0)
- `vtpGetSyncPktLen()` - **Fixed:** uses default (28)
- `vtpGetPayloadEnableArray()` - **Workaround:** always returns NULL (safe default)

**Impact:** These limitations have been worked around using config file parsing and documented defaults. No functionality is lost.

## Version History

- **Feb 2026** - Fixed undefined symbol errors by removing non-existent `vtpGet*()` calls
- **Feb 2026** - Made firmware filenames config-driven (removed hardcoded defaults)
- **Feb 2026** - Added VTP statistics environment variable override support
- **Earlier** - Initial VTP streaming ROL implementation

## References

- [CODA Documentation](https://coda.jlab.org/)
- [VTP Hardware Manual](https://hallaweb.jlab.org/wiki/index.php/VTP)
- `config/base.cnf` - Base configuration template
- `coda_scripts/README.md` - CODA startup scripts documentation

---

**Last Updated:** February 2026
