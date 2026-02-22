# startCoda Argument Parsing Changes

## Overview
This document describes the behavior changes made to the `startCoda` command-line tool to simplify its argument handling and make the interface more deterministic.

## Changes Summary

### 1. --file is Now MANDATORY

**Previous Behavior:**
- `--file` was optional
- If not provided, startCoda would use a default behavior (launch platform, startXterms, startRcgui)

**New Behavior:**
- `--file <path>` is **REQUIRED** for all executions
- If `--file` is not provided, the program fails immediately with:
  ```
  Error: --file is required to start CODA.
  ```
- Exits with non-zero status code (1)

**Rationale:**
- Enforces explicit configuration
- Eliminates hidden default behavior
- Makes component launching deterministic and traceable

### 2. --config Takes NO Parameters

**Previous Behavior:**
- `--config <value>` required a configuration name/value
- The value was used to set CODA_CONFIG environment variable
- Would fail if no value provided

**New Behavior:**
- `--config` is now a **FLAG** (takes no parameters)
- If parameters are provided, they are **ignored** with a warning:
  ```
  WARNING: --config does not take parameters. Ignoring provided value(s).
  ```
- Does NOT fail when parameters are provided (just warns and ignores)

**Rationale:**
- Simplifies the interface (boolean flag vs. string parameter)
- Config directory is already available via $CODA_CONFIG environment variable
- More intuitive: "enable config generation" vs. "set config name"

### 3. --config Behavior

**When --config is present:**
1. Runs pedestal measurement stage (`runfadc250ped` via ROC component xterms)
2. Uses `base.cnf` together with pedestal measurement results
3. Generates configuration files for:
   - VME components: `vme_<hostname>.cnf`
   - VTP components: `vtp_<hostname>.cnf`

**When --config is missing:**
- Does NOT generate any configuration files
- Simply uses the file provided via `--file` to start CODA components normally

### 4. Updated Help Output

The help message (`-h` or `--help`) now clearly documents:
- `--file <path>` is **REQUIRED**
- `--config` takes **NO parameters**
- What `--config` does when present
- Two usage examples showing both modes

## Usage Examples

### Example 1: Start CODA Without Config Generation
```bash
startCoda --file run.cnf
```
- Starts CODA components defined in run.cnf
- Does NOT run pedestal measurement
- Does NOT generate vme_*.cnf or vtp_*.cnf files
- Output: "Config generation: DISABLED"

### Example 2: Start CODA With Config Generation
```bash
startCoda --file run.cnf --config
```
- Starts CODA components defined in run.cnf
- Runs pedestal measurement for ROC components
- Generates vme_<hostname>.cnf and vtp_<hostname>.cnf using base.cnf + pedestal data
- Output: "Config generation: ENABLED (pedestal measurement + VME/VTP config files)"

### Example 3: Invalid - No --file (Will Fail)
```bash
startCoda
```
- **Fails immediately** with error:
  ```
  Error: --file is required to start CODA.
  ```
- Exit code: 1

### Example 4: --config With Parameter (Warns and Ignores)
```bash
startCoda --file run.cnf --config myconfig
```
- **Warns**: "WARNING: --config does not take parameters. Ignoring provided value(s)."
- Continues execution (does not fail)
- Behaves same as `startCoda --file run.cnf --config`

## Implementation Details

### Changed Variables
- `CONFIG_VALUE` → `CONFIG_FLAG`
  - Was: String containing configuration name
  - Now: Boolean flag ("true" or empty string)

### Removed Code
- Default behavior fallback when `--file` not provided:
  ```bash
  # REMOVED:
  if [[ -z "$COMPONENT_FILE" ]]; then
      platform &
      sleep 10
      startXterms &
      startRcgui &
      exit 0
  fi
  ```

- Config value environment export:
  ```bash
  # REMOVED:
  if [[ -n "$CONFIG_VALUE" ]]; then
      export CODA_CONFIG="$CONFIG_VALUE"
  fi
  ```

### Added Code

**Mandatory --file validation:**
```bash
if [[ -z "$COMPONENT_FILE" ]]; then
    echo "Error: --file is required to start CODA."
    echo ""
    usage
    exit 1
fi
```

**--config parameter warning:**
```bash
--config)
    CONFIG_FLAG="true"
    # Check if next argument looks like a parameter
    if [[ -n "$2" && "$2" != --* ]]; then
        echo "WARNING: --config does not take parameters. Ignoring provided value(s)."
        shift 2  # Skip the provided argument
    else
        shift 1  # Just shift past --config
    fi
    ;;
```

**Updated status output:**
```bash
echo "Starting CODA components from file: $RESOLVED_FILE"
if [[ -n "$CONFIG_FLAG" ]]; then
    echo "Config generation: ENABLED (pedestal measurement + VME/VTP config files)"
else
    echo "Config generation: DISABLED"
fi
```

## Validation Order

The script validates arguments in this order:

1. **Parse all command-line arguments**
   - Process `--file`, `--config`, `-h/--help`
   - Warn if `--config` given parameters (but don't fail)
   - Fail on unknown options

2. **Validate --file is provided** ← **FAIL FAST HERE**
   - If missing: error and exit immediately
   - If provided: continue to next step

3. **Resolve and validate file path**
   - Expand environment variables
   - Check file exists and is readable
   - If invalid: error and exit

4. **Process --config logic**
   - If flag set: enable config file generation
   - If flag not set: skip config file generation

5. **Launch components and optionally generate configs**

## Testing

A validation test script is provided: `test_startcoda_validation.sh`

**Test Results:**
```
✓ PASS: Correctly fails with error when --file is missing
✓ PASS: Warning displayed when --config given a parameter
✓ PASS: Help output contains updated documentation
```

**Run tests:**
```bash
cd $CODA_SCRIPTS
./test_startcoda_validation.sh
```

## Migration Guide

### For Users

**If you were running:**
```bash
startCoda                                    # OLD - default behavior
```

**You must now run:**
```bash
startCoda --file <your_components_file>      # NEW - explicit file required
```

**If you were running:**
```bash
startCoda --file run.cnf --config myconfig   # OLD - config with name
```

**You should now run:**
```bash
startCoda --file run.cnf --config            # NEW - config as flag
```
(Note: The old command will still work but will show a warning)

### For Scripts

**Update any automated scripts** that call startCoda:

**Before:**
```bash
#!/bin/bash
startCoda  # Relied on default behavior
```

**After:**
```bash
#!/bin/bash
startCoda --file $CODA_SCRIPTS/default_components.txt
```

**Before:**
```bash
startCoda --file components.txt --config production
```

**After:**
```bash
startCoda --file components.txt --config
```

## Backward Compatibility Notes

### Breaking Changes
1. ❌ Running without `--file` now fails (was: used default behavior)
2. ⚠️ `--config <value>` now warns and ignores the value (was: used the value)

### Non-Breaking
- ✅ `--file <path>` works exactly as before
- ✅ Help output (`-h`, `--help`) still works
- ✅ Component file format unchanged
- ✅ Environment variable resolution in paths still works
- ✅ Config file generation logic unchanged (only trigger mechanism changed)

## Benefits

1. **Clarity**: Explicit requirements eliminate confusion about default behavior
2. **Determinism**: Every invocation requires explicit component file
3. **Simplicity**: `--config` is a simple enable/disable flag
4. **Fail-fast**: Missing `--file` fails immediately before any processing
5. **Traceability**: All runs explicitly specify what components to launch
6. **Error prevention**: Reduces accidental launches with wrong configuration

## Related Documentation

- **README.md**: Updated with new usage examples
- **STAGE2_CHANGES.md**: Config file generation implementation details
- **STAGE3_CHANGES.md**: ROL code modifications for config handling
- **test_startcoda_validation.sh**: Automated validation tests

---

**Last Updated:** February 2026
**Changes Version:** Argument Parsing v2.0
