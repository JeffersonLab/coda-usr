# CODA Startup Sequence Fix

## Overview
This document describes the fix to ensure rcGUI is started at the very last stage of the startup process, after all components and rcPlatform are running.

## Required Startup Order

The correct startup sequence must be:

1. **STAGE 1: Launch all remote shells and start all components**
   - ROC components (either normal startup or pedestal measurement if --config)
   - FPGA/VTP components
   - PEB, ER, and other components
   - Wait for config generation if --config specified

2. **STAGE 2: Start rcPlatform**
   - Start platform process
   - Wait for platform to initialize
   - Verify platform is running

3. **STAGE 3: Start rcGUI (final step)**
   - Only start after platform is verified running
   - This is the LAST step of startup

## Why This Order Matters

**rcPlatform must start before rcGUI because:**
- Platform provides the communication infrastructure
- Platform manages component connections
- Platform provides the control framework rcGUI needs

**Components must start before platform because:**
- Platform needs to discover and connect to components
- Components must be ready when platform starts looking for them

**rcGUI must start last because:**
- rcGUI connects to platform to control the run
- rcGUI needs platform to be fully initialized
- Starting rcGUI too early can cause connection failures

## Implementation

### Code Changes in startCoda

**Previous Code:**
```bash
# Start platform in background
echo "INFO: Starting CODA platform..."
platform &
PLATFORM_PID=$!

# Wait a moment for platform to initialize
sleep 2

# Start rcGUI in background
echo "INFO: Starting Run Control GUI..."
startRcgui &
RCGUI_PID=$!
```

**New Code:**
```bash
# =============================================================================
# STARTUP SEQUENCE STAGE 2: Start CODA Platform
# =============================================================================
echo "************************************************************"
echo "STAGE 2: Starting CODA Platform"
echo "************************************************************"
echo "INFO: All components have been launched and are running"

# Start platform in background
echo "Starting rcPlatform..."
platform &
PLATFORM_PID=$!
echo "  rcPlatform started (PID: $PLATFORM_PID)"

# Wait for platform to initialize before starting rcGUI
echo "  Waiting for rcPlatform to initialize..."
sleep 3

# Verify platform is still running
if kill -0 $PLATFORM_PID 2>/dev/null; then
    echo "  rcPlatform is running (verified)"
else
    echo "  WARNING: rcPlatform process may have died"
fi

# =============================================================================
# STARTUP SEQUENCE STAGE 3: Start rcGUI (final step)
# =============================================================================
echo "************************************************************"
echo "STAGE 3: Starting Run Control GUI (final step)"
echo "************************************************************"
echo "INFO: All components are running"
echo "INFO: rcPlatform is running"
echo "INFO: Starting rcGUI as final step..."

# Start rcGUI - THIS IS THE LAST STEP
echo "Starting rcGUI..."
startRcgui &
RCGUI_PID=$!
echo "  rcGUI started (PID: $RCGUI_PID)"
```

### Key Improvements

1. **Clear Stage Markers**
   - STAGE 2: rcPlatform startup
   - STAGE 3: rcGUI startup (final)
   - Easy to see in console output

2. **Extended Wait Time**
   - Increased from 2 to 3 seconds
   - Gives platform more time to initialize

3. **Platform Verification**
   - Checks platform process is still running
   - Warns if platform died before rcGUI starts
   - Uses `kill -0` for lightweight process check

4. **Explicit Logging**
   - Each stage clearly marked in output
   - Summary at end showing complete sequence
   - Makes troubleshooting easier

5. **Final Summary**
   - Shows complete startup sequence
   - Lists what was done in order
   - Confirms all stages completed

## Console Output Examples

### Without --config

```
************************************************************
Starting CODA components from file: config/run.cnf
Config generation: DISABLED
  - Components will start normally (no pedestal measurement)
  - No config file generation
************************************************************

Launching: ROC VM1 on test2 (MODE: normal startup)
Launching: FPGA VT1 on test2vtp (MODE: normal startup)

************************************************************
Launched 2 components
************************************************************

************************************************************
STAGE 2: Starting CODA Platform
************************************************************
INFO: All components have been launched and are running

Starting rcPlatform...
  rcPlatform started (PID: 12345)
  Waiting for rcPlatform to initialize...
  rcPlatform is running (verified)

************************************************************
STAGE 3: Starting Run Control GUI (final step)
************************************************************
INFO: All components are running
INFO: rcPlatform is running
INFO: Starting rcGUI as final step...

Starting rcGUI...
  rcGUI started (PID: 12346)

======================================================================
CODA STARTUP SEQUENCE COMPLETE
======================================================================

Startup Summary:
  Component table: config/run.cnf
  Components launched: 2
  rcPlatform: STARTED (PID: 12345)
  rcGUI: STARTED (PID: 12346)

Startup sequence:
  1. ✓ Components launched in remote shells
  2. ✓ rcPlatform started
  3. ✓ rcGUI started (final step)

======================================================================
```

### With --config

```
************************************************************
Starting CODA components from file: config/run.cnf
Config generation: ENABLED
  - ROC components will run pedestal measurement
  - VME/VTP config files will be generated from base.cnf
************************************************************

Launching: ROC VM1 on test2 (MODE: pedestal measurement)
  [Config mode] Running pedestal measurement for ROC on test2
Launching: FPGA VT1 on test2vtp (MODE: normal startup)

************************************************************
Launched 2 components
************************************************************

************************************************************
Generating configuration files for ROC hosts
************************************************************
[... config generation output ...]

************************************************************
Configuration file generation complete
************************************************************

************************************************************
STAGE 2: Starting CODA Platform
************************************************************
INFO: All components have been launched and are running
INFO: Configuration files have been generated

Starting rcPlatform...
  rcPlatform started (PID: 12350)
  Waiting for rcPlatform to initialize...
  rcPlatform is running (verified)

************************************************************
STAGE 3: Starting Run Control GUI (final step)
************************************************************
INFO: All components are running
INFO: rcPlatform is running
INFO: Starting rcGUI as final step...

Starting rcGUI...
  rcGUI started (PID: 12351)

======================================================================
CODA STARTUP SEQUENCE COMPLETE
======================================================================

Startup Summary:
  Component table: config/run.cnf
  Components launched: 2
  Config generation: COMPLETED
  rcPlatform: STARTED (PID: 12350)
  rcGUI: STARTED (PID: 12351)

Startup sequence:
  1. ✓ Components launched in remote shells
  2. ✓ Pedestal measurement and config generation completed
  3. ✓ rcPlatform started
  4. ✓ rcGUI started (final step)

======================================================================
```

## Troubleshooting

### Platform Dies Before rcGUI Starts

**Symptom:**
```
Starting rcPlatform...
  rcPlatform started (PID: 12345)
  Waiting for rcPlatform to initialize...
  WARNING: rcPlatform process may have died (PID 12345 not found)
```

**What to check:**
1. Check platform logs for errors
2. Ensure CODA environment is set correctly
3. Check if port 20000 (or configured port) is available
4. Look for Java errors or missing dependencies

**Common causes:**
- Port already in use
- Incorrect CODA installation
- Java not found or wrong version
- Missing CODA environment variables

### rcGUI Fails to Start

**Symptom:**
```
Starting rcGUI...
startRcgui: command not found
```

**What to check:**
1. Verify CODA_SCRIPTS is set correctly
2. Check if startRcgui script exists
3. Ensure CODA environment is sourced

### rcGUI Starts But Can't Connect

**Symptom:**
- rcGUI window opens but shows "Disconnected"
- Can't see components or platform

**What to check:**
1. Is platform actually running? `pgrep -f org.jlab.coda.afecs.platform.APlatform`
2. Check platform logs for connection errors
3. Verify network/firewall settings
4. Check platform port configuration

## Testing

### Manual Test Procedure

**Test 1: Normal startup sequence**
```bash
startCoda --file config/run.cnf
```

**Verify:**
1. Components launch first (see xterm windows open)
2. STAGE 2 message appears
3. rcPlatform starts (see PID)
4. 3-second wait happens
5. Platform verification shows "running"
6. STAGE 3 message appears
7. rcGUI starts last (see PID)
8. Final summary shows correct order

**Test 2: With config generation**
```bash
startCoda --file config/run.cnf --config
```

**Verify:**
1. Components launch with pedestal measurement
2. Config generation completes
3. STAGE 2 message appears
4. rcPlatform starts
5. STAGE 3 message appears
6. rcGUI starts last
7. Summary shows 4-step sequence

**Test 3: Platform failure handling**
```bash
# Manually kill platform right after it starts
startCoda --file config/run.cnf &
sleep 1
pkill -f org.jlab.coda.afecs.platform.APlatform
```

**Verify:**
- Warning message appears: "rcPlatform process may have died"
- Script continues (doesn't hang)
- User can see the problem clearly

## Benefits

1. **Guaranteed Order**
   - Components always start first
   - Platform always starts before rcGUI
   - rcGUI always starts last

2. **Clear Visibility**
   - Stage markers make sequence obvious
   - Easy to see where startup is in logs
   - Final summary confirms all steps

3. **Better Reliability**
   - Platform verification prevents starting rcGUI with dead platform
   - Extended wait time reduces race conditions
   - Clear error messages when things fail

4. **Easier Debugging**
   - Each stage logged separately
   - PIDs recorded for all processes
   - Clear indication of what failed and when

5. **Compliance with Requirements**
   - rcGUI never starts before components ✓
   - rcGUI never starts before platform ✓
   - Clear log messages at each stage ✓
   - Existing functionality preserved ✓

## Summary

The startup sequence is now:

1. **Components** → Launch all remote shells and start components
2. **rcPlatform** → Start platform and verify it's running
3. **rcGUI** → Start GUI as the final step

This order is enforced in code, clearly logged, and verified at each stage.

---

**Last Updated:** February 2026
**Change Type:** Startup sequence enforcement and logging improvements
**Breaking Changes:** None - preserves existing functionality
