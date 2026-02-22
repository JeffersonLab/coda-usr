# CODA_COMPONENT_TABLE Complete Removal from External Usage

## Overview
This document describes the complete removal of `CODA_COMPONENT_TABLE` environment variable from user-facing usage in startCoda and kcoda.

## Key Changes

### What Changed

**BEFORE:**
```bash
# Users had to set this environment variable
export CODA_COMPONENT_TABLE=/path/to/components.txt

# Then run commands
startCoda --file /path/to/components.txt
kcoda  # Used CODA_COMPONENT_TABLE from environment
```

**NOW:**
```bash
# No environment variable needed - just use --file
startCoda --file /path/to/components.txt
kcoda --file /path/to/components.txt
```

### Summary

1. **`CODA_COMPONENT_TABLE` is NOT used from user environment**
   - Users should NEVER set this variable
   - Remove it from your shell configuration files
   - Remove it from setup scripts

2. **Both startCoda and kcoda require `--file`**
   - `--file` argument is mandatory for both commands
   - No fallback to environment variable
   - Clear error if `--file` not provided

3. **Internal usage only**
   - `CODA_COMPONENT_TABLE` is still used internally
   - Automatically exported from `--file` by startCoda/kcoda
   - Used for compatibility with helper scripts (kill_remotes.sh, coda_conf_functions)
   - Users never see or interact with it

## Files Modified

### 1. startCoda
- Already required `--file` (no change to that)
- Updated help text to clarify CODA_COMPONENT_TABLE not used externally
- Updated comments to emphasize internal-only usage

### 2. kcoda
- **BREAKING CHANGE**: Now requires `--file` argument
- No longer accepts CODA_COMPONENT_TABLE from environment
- Added help text with `--help` option
- Exports CODA_COMPONENT_TABLE internally for kill_remotes.sh

### 3. coda_conf_functions
- Updated error message to guide users
- Explains that CODA_COMPONENT_TABLE should not be set by users
- Points users to use startCoda/kcoda with `--file`

### 4. Documentation
- README.md: Updated environment variables section
- COMPONENT_TABLE_ENV_REMOVAL.md: Updated to reflect complete removal
- All help text updated

## Migration Required

### Action Items for Users

**REQUIRED ACTIONS:**

1. **Remove CODA_COMPONENT_TABLE from environment setup**
   ```bash
   # Find and remove lines like this from your .bashrc, .bash_profile, etc.:
   export CODA_COMPONENT_TABLE=/path/to/components.txt
   ```

2. **Update kcoda usage**
   ```bash
   # OLD (will fail):
   kcoda

   # NEW (required):
   kcoda --file /path/to/components.txt
   ```

3. **Update any scripts that use kcoda**
   ```bash
   # OLD:
   export CODA_COMPONENT_TABLE=/path/to/components.txt
   kcoda

   # NEW:
   kcoda --file /path/to/components.txt
   ```

## Breaking Changes

### ⚠️ kcoda Breaking Change

**Previous behavior:**
```bash
# This worked:
export CODA_COMPONENT_TABLE=/path/to/components.txt
kcoda
```

**New behavior:**
```bash
# This is now REQUIRED:
kcoda --file /path/to/components.txt

# This will FAIL:
export CODA_COMPONENT_TABLE=/path/to/components.txt
kcoda
# Error: --file is required to kill CODA components.
```

### No Breaking Changes for startCoda

startCoda already required `--file`, so existing usage continues to work:
```bash
# This always worked and still works:
startCoda --file /path/to/components.txt
startCoda --file /path/to/components.txt --config
```

## Error Messages

### When kcoda Called Without --file

```
Error: --file is required to kill CODA components.

Usage: kcoda --file <component_file> [-h|--help]
...
```

### When CODA_COMPONENT_TABLE Not Set (from helper scripts)

```
ERROR: CODA_COMPONENT_TABLE not set!

This variable is set internally by startCoda or kcoda from the --file argument.
You should not set it directly in your environment.

To use CODA components:
  - Start CODA:  startCoda --file /path/to/components.txt
  - Kill CODA:   kcoda --file /path/to/components.txt
```

## Testing

### Automated Tests

Run the test suite:
```bash
cd $CODA_SCRIPTS
./test_kcoda_changes.sh
```

**Expected results:**
```
✓ PASS: kcoda REQUIRES --file argument (mandatory)
✓ PASS: kcoda does NOT use CODA_COMPONENT_TABLE from environment
✓ PASS: kcoda shows helpful error when --file not provided
✓ PASS: kcoda exports CODA_COMPONENT_TABLE internally for kill_remotes.sh
✓ PASS: External CODA_COMPONENT_TABLE is completely ignored
```

### Manual Testing

**Test 1: kcoda without --file fails**
```bash
unset CODA_COMPONENT_TABLE
kcoda
# Expected: Error: --file is required to kill CODA components.
```

**Test 2: kcoda with --file works**
```bash
kcoda --file /path/to/components.txt
# Expected: Kills components successfully
```

**Test 3: External CODA_COMPONENT_TABLE is ignored**
```bash
export CODA_COMPONENT_TABLE=/some/file.txt
kcoda
# Expected: Error: --file is required (env var ignored)
```

**Test 4: startCoda continues to work**
```bash
unset CODA_COMPONENT_TABLE
startCoda --file /path/to/components.txt
# Expected: Works as before
```

## FAQ

### Q: Why was CODA_COMPONENT_TABLE removed from external usage?

**A:**
- Simplifies user setup (one less environment variable)
- Eliminates potential for mismatch between env var and --file
- Makes component table source explicit and traceable
- Reduces configuration errors

### Q: Can I still set CODA_COMPONENT_TABLE in my environment?

**A:**
No. It will be ignored. Use `--file` instead.

### Q: What if I have scripts that set CODA_COMPONENT_TABLE?

**A:**
Remove those lines and update the scripts to use `--file`:
```bash
# OLD:
export CODA_COMPONENT_TABLE=/path/to/components.txt
kcoda

# NEW:
kcoda --file /path/to/components.txt
```

### Q: Is CODA_COMPONENT_TABLE still used anywhere?

**A:**
Yes, but only internally. startCoda and kcoda export it automatically for compatibility with helper scripts like kill_remotes.sh. Users never need to interact with it.

### Q: What about backward compatibility?

**A:**
- startCoda: No breaking changes (already required --file)
- kcoda: **Breaking change** - now requires --file
- Helper scripts (kill_remotes.sh, coda_conf_functions): No changes needed

### Q: How do I update my workflow?

**A:**
```bash
# 1. Remove CODA_COMPONENT_TABLE from environment setup
# Edit ~/.bashrc or setupCODA3.bash and remove:
# export CODA_COMPONENT_TABLE=...

# 2. Update kcoda calls to use --file
# OLD: kcoda
# NEW: kcoda --file $CODA_SCRIPTS/components.txt

# 3. startCoda usage unchanged
startCoda --file $CODA_SCRIPTS/components.txt
```

## Benefits

1. **Simpler Setup**
   - One less environment variable to configure
   - Less room for user error

2. **Explicit Configuration**
   - Component table always specified via --file
   - No hidden dependencies on environment

3. **Consistency**
   - Both startCoda and kcoda use same interface
   - Symmetric start/stop commands

4. **Better Error Messages**
   - Clear guidance when --file missing
   - Helpful instructions for users

5. **Maintainability**
   - Single source of truth (--file)
   - Easier to debug issues
   - Less ambiguity in configuration

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| **User sets CODA_COMPONENT_TABLE** | Yes, required | No, do NOT set |
| **startCoda --file** | Required | Required (no change) |
| **kcoda --file** | Optional (used env var) | **Required** |
| **Internal export** | No | Yes (for compatibility) |
| **Environment cleanup needed** | N/A | Yes, remove CODA_COMPONENT_TABLE |

## Related Documentation

- `README.md` - Updated environment variables section
- `COMPONENT_TABLE_ENV_REMOVAL.md` - Original removal documentation (now updated)
- `test_kcoda_changes.sh` - Automated test suite
- `startCoda --help` - Updated help text
- `kcoda --help` - New help text

---

**Last Updated:** February 2026
**Change Type:** Complete removal of external CODA_COMPONENT_TABLE usage
**Breaking Changes:** kcoda now requires --file argument
