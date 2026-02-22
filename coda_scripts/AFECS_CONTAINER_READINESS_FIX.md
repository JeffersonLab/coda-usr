# AFECS Container Readiness Fix - Race Condition Elimination

## Critical Problem Discovered

### The Race Condition

**Observed Behavior (from console logs):**
```
16:03:36 - rcPlatform banner appears
16:03:39 - rcGUI starts (3 seconds after platform)
16:03:39 - rcGUI FAILS: "Problem communicating with the Platform"
16:03:42 - AFECS container registers:
           "Afecs-4 Container"
           "Name = clondaq3.jlab.org_admin"
           "Connected to: Platform Name = vgexpid"
16:03:42+ - Manual rcGUI launch now SUCCEEDS
```

**Root Cause:**
rcGUI was started 3 seconds after rcPlatform started, based on:
- Process existence check (platform PID exists)
- Fixed 3-second sleep

However, the platform is **NOT** ready for rcGUI connections until the AFECS container registers, which can take 6+ seconds.

**The Problem:**
- rcPlatform prints banner → Platform process exists ✓
- TCP port opens → Port is listening ✓
- **BUT**: AFECS container not yet registered → Platform NOT ready ✗
- rcGUI tries to connect → **FAILS**

## Why AFECS Container Registration Matters

### What is the AFECS Container?

The AFECS (Accelerator Front End Control System) container is a critical component that:
- Manages communication between platform and components
- Handles admin/control agent registration
- Provides the infrastructure for rcGUI to communicate with platform
- Named as `<hostname>_admin` (e.g., `clondaq3.jlab.org_admin`)

### Platform Startup Sequence

1. **Platform process starts** (PID created)
2. **Platform banner prints** (stdout message)
3. **TCP/UDP ports open** (port 45000, etc.)
4. **Internal initialization** (3-6 seconds)
5. **AFECS container starts and registers** ← **CRITICAL POINT**
6. **Platform ready for rcGUI**

The problem was that we were starting rcGUI at step 3, but the platform isn't ready until step 5.

## The Solution

### Implementation

**Instead of:**
```bash
# OLD CODE (BUGGY):
platform &
PLATFORM_PID=$!
sleep 3  # Fixed wait - race condition!
# Start rcGUI here - may fail if container not ready
startRcgui &
```

**Now:**
```bash
# NEW CODE (FIXED):
platform &
PLATFORM_PID=$!

# Wait for AFECS container registration (deterministic)
echo "Waiting for AFECS container to register..."

MAX_WAIT=30
WAIT_COUNT=0
AFECS_READY=false

while [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
    # Check platform log for container registration
    if grep -q "Afecs-4 Container" "$PLATFORM_LOG" 2>/dev/null; then
        if grep -q "_admin" "$PLATFORM_LOG" 2>/dev/null; then
            AFECS_READY=true
            echo "✓ AFECS container registered — platform ready for rcGUI"
            break
        fi
    fi

    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Only start rcGUI after container is confirmed ready
if [[ "$AFECS_READY" == "true" ]]; then
    startRcgui &
else
    echo "WARNING: AFECS container did not register within ${MAX_WAIT} seconds"
    # Provide diagnostics and abort if platform died
fi
```

### Key Features

1. **Deterministic Wait**
   - No fixed sleep
   - Polls platform log for actual container registration
   - Retry loop with timeout

2. **Signature Detection**
   - Looks for: `"Afecs-4 Container"`
   - Verifies: `"_admin"` agent registration
   - Confirms: Platform is ready for connections

3. **Timeout Handling**
   - Maximum wait: 30 seconds
   - Clear error if timeout occurs
   - Diagnostic information provided

4. **Platform Health Monitoring**
   - Checks if platform process is still alive
   - Aborts if platform dies during wait
   - Shows platform log location for troubleshooting

5. **Progress Indication**
   - Dots printed as log grows (activity indicator)
   - Final confirmation when container registers
   - Shows how long initialization took

## Console Output

### Successful Startup

```
************************************************************
STAGE 2: Starting CODA Platform
************************************************************
INFO: All components have been launched and are running

Starting rcPlatform...
  rcPlatform started (PID: 12345)

  Waiting for AFECS container to register...
  (Platform is not ready for rcGUI until container registers)
.....
  ✓ AFECS container registered — platform ready for rcGUI
    Container: clondaq3.jlab.org_admin
  Platform initialization: COMPLETE (6 seconds)

************************************************************
STAGE 3: Starting Run Control GUI (final step)
************************************************************
INFO: All components are running
INFO: rcPlatform is running and AFECS container registered
INFO: Platform is ready - starting rcGUI as final step...

Starting rcGUI...
  rcGUI started (PID: 12346)
```

### Timeout Scenario

```
Starting rcPlatform...
  rcPlatform started (PID: 12345)

  Waiting for AFECS container to register...
  (Platform is not ready for rcGUI until container registers)
..............................

  WARNING: AFECS container did not register within 30 seconds
  Platform may not be fully ready for rcGUI
  Check platform log: /path/to/dlog/platformDlog
  Platform process is still running (PID: 12345)
  Proceeding with rcGUI startup (may fail if platform not ready)
```

### Platform Died During Startup

```
Starting rcPlatform...
  rcPlatform started (PID: 12345)

  Waiting for AFECS container to register...
...
  ERROR: rcPlatform process died (PID 12345 not found)
  Cannot proceed to rcGUI startup
```

## Platform Log Location

### Default Location

The platform log is determined from environment variables:
```bash
PLATFORM_LOG="${CODA_DATA}/${EXPID}/dlog/platformDlog"
```

**Example:**
```
/data/coda/vgexpid/dlog/platformDlog
```

### Requirements

For proper AFECS container detection, ensure:
```bash
export CODA_DATA=/path/to/coda/data
export EXPID=vgexpid  # Your experiment ID
```

### Fallback

If `CODA_DATA` not set, tries:
```bash
PLATFORM_LOG="./${EXPID}/dlog/platformDlog"
```

### Log Content Example

Platform log shows container registration:
```
=================================================
        Afecs-4 Container                  *


Name = clondaq3.jlab.org_admin

Host = clondaq3.jlab.org

Start time = 2026/02/22 16:03:42

Connected to:

Platform Name = vgexpid

Platform Host = clondaq3.jlab.org

Platform TCP port = 45000

Platform UDP port = 45000

Platform RC UDP port = 45200
=================================================
```

The code looks for:
1. `"Afecs-4 Container"` - Container type header
2. `"_admin"` - Admin agent registration

## Timing Analysis

### Before Fix (Race Condition)

```
T+0s:  Platform starts
T+0s:  Banner prints
T+1s:  Port opens
T+3s:  rcGUI starts ← TOO EARLY
T+3s:  rcGUI fails: "Problem communicating with the Platform"
T+6s:  AFECS container registers ← Platform actually ready
T+6s+: Manual rcGUI works
```

**Problem:** 3-second gap between when we start rcGUI and when platform is actually ready.

### After Fix (Deterministic)

```
T+0s:  Platform starts
T+0s:  Banner prints
T+1s:  Port opens
T+0-6s: Polling for AFECS container (dynamic wait)
T+6s:  AFECS container registers ✓
T+6s:  rcGUI starts ← CORRECT TIMING
T+6s+: rcGUI connects successfully ✓
```

**Solution:** Wait for actual container registration, not a fixed time.

## Benefits

1. **Eliminates Race Condition**
   - No more "Problem communicating with the Platform" errors
   - rcGUI only starts when platform is truly ready
   - Deterministic startup sequence

2. **Faster When Possible**
   - If container registers in 4 seconds, rcGUI starts at 4 seconds
   - If container takes 8 seconds, rcGUI waits 8 seconds
   - Optimal timing in all cases

3. **Better Diagnostics**
   - Shows exactly what we're waiting for
   - Progress indication (dots)
   - Clear confirmation when ready
   - Helpful error messages if problems occur

4. **Robust Error Handling**
   - Detects if platform dies during startup
   - Timeout prevents infinite wait
   - Points user to log file for troubleshooting

5. **No Breaking Changes**
   - Preserves all existing functionality
   - Just adds proper readiness detection
   - Backwards compatible

## Environment Requirements

### Required Variables

```bash
export CODA_DATA=/path/to/coda/data  # For platform log location
export EXPID=vgexpid                 # Experiment ID
```

### Without These Variables

The code will:
- Try fallback log location
- Show warning if log not found
- Still proceed (may fail if platform not ready)
- Provide guidance on setting variables

## Troubleshooting

### AFECS Container Never Registers

**Symptom:**
```
WARNING: AFECS container did not register within 30 seconds
```

**What to check:**
1. Platform log file location: `$CODA_DATA/$EXPID/dlog/platformDlog`
2. Platform actually running: `pgrep -f org.jlab.coda.afecs.platform`
3. Platform errors in log
4. Network/port issues
5. CODA environment setup

**Common causes:**
- Platform configuration errors
- Port already in use (45000)
- Missing CODA components
- Environment variables not set

### Platform Dies During Startup

**Symptom:**
```
ERROR: rcPlatform process died (PID 12345 not found)
```

**What to check:**
1. Platform log for errors
2. Java errors/exceptions
3. Missing dependencies
4. Port conflicts

### Log File Not Found

**Symptom:**
```
Could not determine platform log location
Set CODA_DATA and EXPID environment variables
```

**Fix:**
```bash
export CODA_DATA=/your/coda/data/path
export EXPID=your_expid
```

## Testing

### Test 1: Normal Startup

```bash
export CODA_DATA=/path/to/coda/data
export EXPID=vgexpid
startCoda --file config/run.cnf
```

**Verify:**
- "Waiting for AFECS container to register..." appears
- Dots printed as platform initializes
- "✓ AFECS container registered" appears
- Container name shown (e.g., `clondaq3.jlab.org_admin`)
- "Platform initialization: COMPLETE (X seconds)" shows actual time
- rcGUI starts only after container ready

### Test 2: Slow Platform

```bash
# If platform takes longer to initialize
# Verify wait continues until container registers
# Should NOT start rcGUI prematurely
```

**Verify:**
- Wait continues past 3 seconds
- rcGUI only starts when container actually ready
- No "Problem communicating with the Platform" error

### Test 3: Platform Failure

```bash
# Kill platform during startup
startCoda --file config/run.cnf &
sleep 2
pkill -f org.jlab.coda.afecs.platform
```

**Verify:**
- Error detected: "rcPlatform process died"
- Startup aborts cleanly
- Clear error message

### Test 4: Timeout

```bash
# If container never registers (platform broken)
# Should timeout after 30 seconds with clear message
```

**Verify:**
- Timeout message after 30 seconds
- Diagnostic information provided
- Points to log file

## Migration Notes

### No User Action Required

This fix is transparent to users:
- Same command: `startCoda --file config/run.cnf`
- Just works more reliably
- No config changes needed

### What Changes

**Before:**
- rcGUI might fail with "Problem communicating with the Platform"
- Users had to manually start rcGUI again
- Race condition made startup unreliable

**After:**
- rcGUI always starts at the right time
- Reliable startup sequence
- No manual intervention needed

## Summary

### The Rule

**rcGUI must start ONLY after:**
1. All components are running
2. rcPlatform is running
3. **AFECS container has registered with platform** ← NEW

This is no longer based on:
- ❌ Fixed time delay
- ❌ Process existence
- ❌ Port availability

It's now based on:
- ✅ Actual container registration
- ✅ Platform log verification
- ✅ Deterministic readiness check

### The Fix

**Before:** `sleep 3` → race condition → rcGUI fails
**After:** Wait for container → deterministic → rcGUI succeeds

---

**Last Updated:** February 2026
**Issue:** Critical race condition causing rcGUI connection failures
**Status:** FIXED with AFECS container readiness detection
