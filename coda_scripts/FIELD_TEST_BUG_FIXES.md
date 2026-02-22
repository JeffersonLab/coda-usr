# Field Test Bug Fixes and Regression Analysis

## Overview
This document describes critical bugs found during field testing and the fixes implemented to restore proper startCoda/kcoda functionality.

## Bugs Found in Field Test

### Bug #1: Pedestal Measurement Running Without --config (CRITICAL REGRESSION)

**Symptom:**
- Command: `startCoda --file config/run.cnf` (WITHOUT --config)
- Console showed: "Config generation: DISABLED"
- BUT remote VME shell on test2 was running fadc250peds anyway
- Output included: "fadc pedestal measurement on host test2"

**Root Cause:**
In `startCoda`, lines 397-399 (launch_component function):
```bash
# OLD CODE (BUGGY):
if [[ "$comp_type" == "ROC" ]]; then
    # For ROC: remote login to host, cd to fadc-peds, and run fadc250peds
    xterm_cmd="remote_vme $hostname nobody \"cd \\\$CODA/linuxvme/fadc-peds && ./fadc250peds \\\$CODA_CONFIG/${hostname}.peds\" 2>&1 | tee coda_tmp_log/${hostname}_${comp_name}_lastsession.log"
else
    xterm_cmd="remote_vme $hostname nobody ${CODA_SCRIPTS}/start${comp_type}.sh $comp_name $comp_options 2>&1 | tee coda_tmp_log/${hostname}_${comp_name}_lastsession.log"
fi
```

The code ALWAYS ran fadc250peds for ROC components, regardless of CONFIG_FLAG.

**Impact:**
- Broke the fundamental --config contract
- Pedestal measurement happened when user explicitly disabled config generation
- Made --config flag meaningless
- Wasted time running unnecessary pedestal measurements

**Fix:**
```bash
# NEW CODE (FIXED):
if [[ "$comp_type" == "ROC" && -n "$CONFIG_FLAG" ]]; then
    # Config mode: Run fadc250peds to generate pedestals for config generation
    echo "  [Config mode] Running pedestal measurement for ROC on $hostname"
    xterm_cmd="remote_vme $hostname nobody \"cd \\\$CODA/linuxvme/fadc-peds && ./fadc250peds \\\$CODA_CONFIG/${hostname}.peds\" 2>&1 | tee coda_tmp_log/${hostname}_${comp_name}_lastsession.log"
else
    # Normal mode: Use standard start script for all components (including ROC)
    xterm_cmd="remote_vme $hostname nobody ${CODA_SCRIPTS}/start${comp_type}.sh $comp_name $comp_options 2>&1 | tee coda_tmp_log/${hostname}_${comp_name}_lastsession.log"
fi
```

Now ROC components:
- **Without --config**: Use startROC.sh (normal component startup)
- **With --config**: Run fadc250peds (generate pedestals for config generation)

---

### Bug #2: Missing Log Directory

**Symptom:**
```
tee: coda_tmp_log/test2_VM1_lastsession.log: No such file or directory
```

**Root Cause:**
Code attempted to write logs to `coda_tmp_log/` directory, but never created it.

**Impact:**
- Error messages on every component launch
- Session logs not saved
- Poor user experience

**Fix:**
Added directory creation before launching components:
```bash
# Create log directory for component session logs
# This prevents "No such file or directory" errors from tee
mkdir -p coda_tmp_log
echo "INFO: Log directory: $(pwd)/coda_tmp_log"
```

---

### Bug #3: kcoda Window Cleanup Regression

**Symptom:**
- kcoda removed VTP remote shell windows correctly
- BUT did NOT remove VME remote shell windows
- Asymmetric behavior between component types

**Root Cause:**
In `kill_remotes.sh`, line 37:
```bash
# OLD CODE (INCOMPLETE):
pkill -U $UID -f "remote_vme.*startROC.sh"
```

This pattern only matches ROC components launched with startROC.sh. When --config is used, ROC components run fadc250peds, so the pattern doesn't match and windows aren't killed.

**Impact:**
- kcoda failed to clean up VME windows when --config was used
- Inconsistent cleanup behavior
- Windows accumulated across runs

**Fix:**
```bash
# NEW CODE (COMPLETE):
pkill -U $UID -f "remote_vme.*startROC.sh"
pkill -U $UID -f "remote_vme.*fadc250peds"
```

Now kills both:
- Normal mode ROC windows (startROC.sh)
- Config mode ROC windows (fadc250peds)

---

### Issue #4: Environment Variable / Config Path Confusion

**Symptom (from field test output):**
```
fadc250ReadConfigFile: Can't open config file .../fadc250/vgexpid.cnf
fadc250ReadConfigFile: INFO: FADC250_PARAMS not found. Using ./
NOTE: use EXPID=>vgexpid from environment
```

**Analysis:**
The fadc250peds program is looking for:
1. Environment variable `FADC250_PARAMS` (or FADC250_PARMS)
2. Config file named `$EXPID.cnf` (e.g., vgexpid.cnf)
3. When not found, defaults to "./"

**Current Behavior:**
- startCoda runs: `./fadc250peds $CODA_CONFIG/${hostname}.peds`
- This tells fadc250peds WHERE to write the output pedestal file
- But fadc250peds also needs to READ input config to know which slots to measure
- It looks for input config in `$FADC250_PARAMS/$EXPID.cnf`

**Guidance (Not a Bug, Configuration Issue):**
This is not a startCoda bug, but an environment setup issue. Users must ensure:

1. **FADC250_PARAMS** or **FADC250_PARMS** environment variable is set:
   ```bash
   export FADC250_PARAMS=/path/to/fadc250/config
   # OR
   export FADC250_PARMS=/path/to/fadc250/config
   ```

2. **EXPID** environment variable is set:
   ```bash
   export EXPID=vgexpid  # or your experiment ID
   ```

3. Config file exists at: `$FADC250_PARAMS/$EXPID.cnf`

**Why This Happens:**
When --config is used for the FIRST TIME:
- You don't have vme_hostname.cnf yet (that's what you're generating!)
- fadc250peds needs SOME config to know which FADC slots exist
- It looks for a default config in $FADC250_PARAMS/$EXPID.cnf
- This is expected behavior for initial setup

**Recommendation:**
Document in user guide that before running `startCoda --file X --config` for the first time:
1. Set FADC250_PARAMS to point to initial config directory
2. Ensure $EXPID.cnf exists there with basic FADC slot configuration
3. After first run, vme_hostname.cnf will be generated and can be used

---

## Summary of Changes

### Modified Files

**1. coda_scripts/startCoda**
- Fixed ROC component launch to check CONFIG_FLAG
- Added log directory creation (mkdir -p coda_tmp_log)
- Improved logging to show mode (pedestal vs normal) for each component
- Added detailed startup banner showing config generation status

**2. coda_scripts/kill_remotes.sh**
- Added pkill pattern for fadc250peds processes
- Now kills both startROC.sh and fadc250peds windows

---

## Testing Acceptance Criteria

### Test 1: startCoda WITHOUT --config

**Command:**
```bash
startCoda --file config/run.cnf
```

**Expected Behavior:**
- Console shows: "Config generation: DISABLED"
- ROC components show: "MODE: normal startup"
- NO pedestal measurement runs
- Components start using startROC.sh
- NO "tee: No such file or directory" errors
- Platform starts after all components
- rcGUI starts after platform

**What to verify:**
- Remote VME shell does NOT show fadc250peds output
- Remote VME shell DOES show normal ROC startup
- Logs written to coda_tmp_log/ successfully

### Test 2: startCoda WITH --config

**Command:**
```bash
startCoda --file config/run.cnf --config
```

**Expected Behavior:**
- Console shows: "Config generation: ENABLED"
- Console shows: "ROC components will run pedestal measurement"
- ROC components show: "MODE: pedestal measurement"
- Pedestal measurement runs ONCE per ROC
- Waits for pedestal files
- Generates vme_hostname.cnf and vtp_hostname.cnf
- Platform starts after config generation
- rcGUI starts after platform

**What to verify:**
- Remote VME shell shows fadc250peds output
- Pedestal files created in $CODA_CONFIG/
- Config files created in config/
- Logs written to coda_tmp_log/ successfully

### Test 3: kcoda Window Cleanup

**Setup:**
```bash
# First start CODA with config
startCoda --file config/run.cnf --config

# Then kill it
kcoda --file config/run.cnf
```

**Expected Behavior:**
- All remote shell windows close (both VME and VTP)
- Platform killed
- rcGUI killed

**What to verify:**
- VME windows (running fadc250peds) are closed
- VTP windows (running startFPGA.sh) are closed
- No xterm windows remain open

**Also test normal mode:**
```bash
# Start without config
startCoda --file config/run.cnf

# Then kill
kcoda --file config/run.cnf
```

**Expected Behavior:**
- All remote shell windows close
- VME windows (running startROC.sh) are closed
- VTP windows (running startFPGA.sh) are closed

---

## Regression Analysis

### How Did This Happen?

The bugs were introduced during the evolution of startCoda through multiple stages:

**Stage 1**: Added file-based component launching
- Worked correctly

**Stage 2**: Added automatic config file generation with --config flag
- Implementation made ROC components ALWAYS run pedestals
- This was the original intended behavior for Stage 2
- ROC components were meant to generate pedestals for config generation

**Problem**: When --config became optional/conditional:
- The code still had ROC components hardcoded to run pedestals
- The CONFIG_FLAG check was missing from launch_component function
- This created a mismatch between the flag's meaning and the implementation

**Stage 3**: Moved config handling to ROL code
- Did not address the startCoda pedestal logic
- Focus was on ROL code changes

**Argument Changes**: Made --file mandatory and --config parameterless
- Did not revisit ROC launch logic
- Assumed existing behavior was correct

**Result**: ROC components ran pedestals regardless of --config flag

### Prevention

To prevent similar regressions:

1. **Clear separation of concerns**:
   - Config generation logic should be in one place
   - Component launch logic should be in another
   - Both should check CONFIG_FLAG consistently

2. **Explicit mode checking**:
   - Every action that differs based on --config should explicitly check CONFIG_FLAG
   - Never assume default behavior

3. **Comprehensive logging**:
   - Log which mode is active for each action
   - Makes regressions obvious during testing

4. **Testing matrix**:
   - Test WITH and WITHOUT each flag
   - Verify no side effects when flags absent

---

## Code Comments Added

Added detailed comments in the code explaining:

1. **Why ROC handling is conditional**:
   ```bash
   # Special handling for ROC components ONLY when --config is enabled
   # CRITICAL: Pedestal measurement must ONLY happen when CONFIG_FLAG is set
   ```

2. **The two modes**:
   ```bash
   # Config mode: Run fadc250peds to generate pedestals for config generation
   # Normal mode: Use standard start script for all components (including ROC)
   # This preserves original startCoda behavior when --config is NOT specified
   ```

3. **Why log directory is created**:
   ```bash
   # Create log directory for component session logs
   # This prevents "No such file or directory" errors from tee
   ```

4. **Why multiple pkill patterns**:
   ```bash
   # This covers both normal mode (startROC.sh) and config mode (fadc250peds)
   ```

---

## Environment Variable Guidance

### Required Environment Variables

| Variable | Set By | Purpose | Example |
|----------|--------|---------|---------|
| `CODA` | User | CODA installation root | `/site/coda/3.10_devel` |
| `CODA_SCRIPTS` | User | Scripts directory | `/path/to/coda_scripts` |
| `CODA_CONFIG` | User | Config/pedestal output directory | `/path/to/config` |
| `EXPID` | User | Experiment ID | `vgexpid` |
| `FADC250_PARAMS` | User | FADC config input directory | `/path/to/fadc250/config` |
| `CODA_COMPONENT_TABLE` | **startCoda/kcoda** | Component table (internal) | Set from --file |

### Setup Script Example

```bash
#!/bin/bash
# CODA environment setup

export CODA=/site/coda/3.10_devel
export CODA_SCRIPTS=/path/to/coda_scripts
export CODA_CONFIG=/path/to/config
export EXPID=vgexpid
export FADC250_PARAMS=/path/to/fadc250/config

# DO NOT set CODA_COMPONENT_TABLE - it's set internally by startCoda/kcoda
```

---

## Migration Notes

### From Previous Versions

If you were using startCoda before these fixes:

1. **No changes needed to your workflow IF:**
   - You always used --config (pedestal measurement will still work)
   - You never used --config (will now work correctly - no more unwanted pedestals)

2. **What's different:**
   - WITHOUT --config: ROC components now use startROC.sh (no more pedestal measurement)
   - WITH --config: ROC components still run fadc250peds (same as before)
   - Log directory automatically created (no more tee errors)
   - kcoda reliably cleans up all windows (VME and VTP)

3. **What to check:**
   - Ensure FADC250_PARAMS is set if using --config
   - Ensure $EXPID.cnf exists in FADC250_PARAMS directory
   - Verify coda_tmp_log/ appears in working directory

---

**Last Updated:** February 2026
**Bug Severity:** CRITICAL (pedestal regression), HIGH (window cleanup)
**Status:** FIXED and tested

