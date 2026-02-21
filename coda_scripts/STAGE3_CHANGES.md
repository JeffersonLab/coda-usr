# Stage 3 Implementation Summary

## Overview
This stage moves configuration and pedestal handling OUT of startup scripts and INTO the ROL (ReadOut List) code. The changes remove runtime pedestal generation and dynamic config file creation from the VME ROL, replacing them with default per-host configuration file usage when userconfig is not explicitly defined.

## Modified Files

### 1. rol/vme_rol/fadc_vme.c
VME FADC readout list - handles VME-based FADC250 module configuration

### 2. rol/vtp_rol/vtp_sro_1udp.c
VTP streaming readout list - handles VTP firmware loading and network configuration

## Detailed Changes

### VME ROL (rol/vme_rol/fadc_vme.c)

#### What Was Removed

**1. Entire Pedestal Generation Block (approximately lines 1169-1356)**
   - Removed `parse_user_config()` function call
   - Removed fork/exec of `fadc250peds` command
   - Removed `waitpid()` and child process monitoring
   - Removed pedestal file generation logic
   - Removed all associated error handling for pedestal generation

**2. Dynamic Configuration File Generation**
   - Removed `generate_vme_config()` call
   - Removed `generate_vtp_config()` call
   - Removed runtime creation of vme_<hostname>.cnf
   - Removed runtime creation of vtp_<hostname>.cnf

**3. Removed Code Pattern**
```c
/* REMOVED CODE */
parse_user_config(rol->usrConfig, &session_name, &config_name);
// ... pedestal generation via fork/exec ...
generate_vme_config(hostname, config_name);
generate_vtp_config(hostname, config_name);
```

#### What Was Added

**Default Configuration File Fallback Logic**

The ROL now checks if `userconfig` is defined and selects the appropriate config file:

```c
/* Check if userconfig is defined */
if (rol->usrConfig && *rol->usrConfig)
{
  /* userconfig is defined - use it (existing behavior) */
  printf("INFO: Using user-specified config file: %s\n", rol->usrConfig);
  snprintf(fadc_config_file, sizeof(fadc_config_file), "%s", rol->usrConfig);
}
else
{
  /* userconfig NOT defined - use default per-host config file */
  char hostname[256];
  printf("INFO: userconfig not defined, using default per-host config file\n");

  if (get_sanitized_hostname(hostname, sizeof(hostname)) != 0)
  {
    printf("ERROR: rocDownload - Failed to get hostname\n");
    return;
  }

  /* Construct default config path: $CODA_CONFIG/vme_<hostname>.cnf */
  snprintf(fadc_config_file, sizeof(fadc_config_file),
           "%s/vme_%s.cnf", coda_config_env, hostname);

  printf("INFO: Using default per-host config file: %s\n", fadc_config_file);
}
```

**Condition for "userconfig not defined":**
- `rol->usrConfig == NULL` OR `*rol->usrConfig == '\0'`
- This checks both pointer validity and empty string

**Default Config File Path:**
- Format: `$CODA_CONFIG/vme_<hostname>.cnf`
- Example: `/path/to/config/vme_test2.cnf`
- Hostname extracted via existing `get_sanitized_hostname()` function

#### Backward Compatibility
When userconfig IS defined (in CODA run control GUI), the existing behavior is preserved - the ROL uses the specified config file exactly as before.

---

### VTP ROL (rol/vtp_rol/vtp_sro_1udp.c)

#### Firmware Path Resolution (rocDownload)

**Changed From:**
```c
/* OLD - hardcoded paths */
sprintf(buf, "%s/src/vtp/firmware/%s", coda, z7file);
sprintf(buf, "%s/src/vtp/firmware/%s", coda, v7file);
```

**Changed To:**
```c
/* NEW - use $CODA_FIRMWARE environment variable */

/* Get CODA_FIRMWARE environment variable (default firmware directory) */
coda_firmware = getenv("CODA_FIRMWARE");
if (!coda_firmware || !*coda_firmware) {
  /* Fallback to $CODA/firmware if CODA_FIRMWARE not set */
  const char *coda = getenv("CODA");
  if (!coda || !*coda) {
    fprintf(stderr, "ERROR: Neither CODA_FIRMWARE nor CODA env vars are set\n");
    return;
  }
  static char fallback_firmware_dir[512];
  snprintf(fallback_firmware_dir, sizeof(fallback_firmware_dir), "%s/firmware", coda);
  coda_firmware = fallback_firmware_dir;
  printf("INFO: CODA_FIRMWARE not set, using fallback: %s\n", coda_firmware);
}

/* Load Z7 firmware */
snprintf(buf, sizeof(buf), "%s/%s", coda_firmware, z7file);
printf("INFO: Loading Z7 firmware: %s\n", buf);

if(access(buf, R_OK) != 0)
{
  printf("ERROR: Z7 firmware file not found or not readable: %s\n", buf);
  printf("ERROR: Check CODA_FIRMWARE environment variable and firmware file\n");
  return;
}

if(vtpZ7CfgLoad(buf) != OK)
{
  printf("ERROR: Z7 firmware failed: %s\n", buf);
  return;
}
printf("INFO: Z7 firmware loaded successfully\n");
```

**Firmware Path Resolution Priority:**
1. Use `$CODA_FIRMWARE` if set
2. Fallback to `$CODA/firmware` if `CODA_FIRMWARE` not set
3. Error if neither environment variable is set

**File Existence Checking:**
- Added `access(buf, R_OK)` checks before loading
- Provides clear error messages if firmware files missing

#### VTP Configuration File Fallback (rocPrestart)

**Added userconfig fallback logic:**

```c
/* Check if userconfig is defined */
if (rol->usrConfig && *rol->usrConfig)
{
  /* userconfig is defined - use it (existing behavior) */
  printf("INFO: Using user-specified VTP config file: %s\n", rol->usrConfig);
  snprintf(vtp_config_path, sizeof(vtp_config_path), "%s", rol->usrConfig);
}
else
{
  /* userconfig NOT defined - use default per-host config file */
  printf("INFO: userconfig not defined, using default per-host VTP config file\n");

  if (vtp_get_generated_config_path(vtp_config_path, sizeof(vtp_config_path)) != 0)
  {
    printf("ERROR: Failed to construct default VTP config path\n");
    return;
  }

  printf("INFO: Using default per-host VTP config: %s\n", vtp_config_path);
}
```

**Default VTP Config File Path:**
- Format: `$CODA_CONFIG/vtp_<hostname>.cnf`
- Example: `/path/to/config/vtp_test2.cnf`
- Hostname extracted via helper function `vtp_get_generated_config_path()`

---

## Environment Variable Assumptions

### Required Environment Variables

**1. CODA_CONFIG**
- **Purpose**: Base directory for configuration files
- **Used by**: Both VME and VTP ROLs
- **Default config paths**:
  - VME: `$CODA_CONFIG/vme_<hostname>.cnf`
  - VTP: `$CODA_CONFIG/vtp_<hostname>.cnf`
- **Must be set**: Yes
- **Example**: `/home/user/config`

**2. CODA_FIRMWARE**
- **Purpose**: Directory containing VTP firmware files
- **Used by**: VTP ROL (rocDownload)
- **Fallback**: `$CODA/firmware` if not set
- **Must be set**: No (will use fallback)
- **Example**: `/home/user/firmware`

**3. CODA**
- **Purpose**: CODA installation root directory
- **Used by**: VTP ROL (fallback for firmware path)
- **Must be set**: Yes (if CODA_FIRMWARE not set)
- **Example**: `/site/coda/3.10_devel`

### Default Behavior When Variables Not Set

**CODA_CONFIG not set:**
- ROL will attempt to use the variable and likely fail
- No explicit fallback implemented (relies on environment setup)

**CODA_FIRMWARE not set:**
- Automatic fallback to `$CODA/firmware`
- Warning message printed to console
- Continues normally if fallback directory contains firmware files

**CODA not set (and CODA_FIRMWARE not set):**
- Error message printed
- ROL returns from rocDownload without loading firmware
- Run will fail

---

## Configuration File Expectations

### VME Configuration Files

**Default location when userconfig not defined:**
```
$CODA_CONFIG/vme_<hostname>.cnf
```

**Expected to contain:**
- VME base configuration (from base.cnf VME section)
- FADC250 pedestal data (appended at end)
- Generated by startCoda script Stage 2 when `--config` parameter used

**Example:**
```bash
# VME configuration section from base.cnf
# ... VME settings ...

# Pedestal data appended from hostname.peds
FADC250_SLOT 3
FADC250_DAC  3297
FADC250_W_OFFSET 3200
# ... pedestal values for all channels ...
```

### VTP Configuration Files

**Default location when userconfig not defined:**
```
$CODA_CONFIG/vtp_<hostname>.cnf
```

**Expected to contain:**
- VTP base configuration (from base.cnf VTP section)
- MAC address (VTP_STREAMING_MAC)
- IP address (VTP_STREAMING_IPADDR)
- VTP_PAYLOAD_EN computed from FADC slots
- Generated by startCoda script Stage 2 when `--config` parameter used

**Example:**
```bash
# VTP configuration section from base.cnf
# ... VTP settings ...

VTP_STREAMING_MAC 0xCE 0xBA 0xF0 0x03 0x00 0x9d
VTP_STREAMING_IPADDR 129 57 69 14
VTP_PAYLOAD_EN 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0
# ... additional VTP streaming settings ...
```

---

## Workflow Changes

### Old Workflow (Stages 1-2)
1. User runs `startCoda --file components.txt --config myconfig`
2. ROC components launch xterms
3. Each xterm SSHs to ROC host and runs `fadc250peds`
4. Pedestal files (hostname.peds) generated on remote hosts
5. startCoda script waits for pedestal files
6. startCoda generates vme_hostname.cnf and vtp_hostname.cnf
7. Later, when CODA run starts, ROLs execute
8. **ROL rocDownload()** generates pedestals AGAIN (now removed)
9. **ROL rocDownload()** generates config files AGAIN (now removed)
10. ROL loads configuration

### New Workflow (Stage 3)
1. User runs `startCoda --file components.txt --config myconfig`
2. ROC components launch xterms
3. Each xterm SSHs to ROC host and runs `fadc250peds`
4. Pedestal files (hostname.peds) generated on remote hosts
5. startCoda script waits for pedestal files
6. **startCoda generates vme_hostname.cnf and vtp_hostname.cnf** (ONE-TIME)
7. Later, when CODA run starts, ROLs execute
8. **ROL rocDownload() checks userconfig:**
   - If userconfig defined: use specified file (backward compatible)
   - If userconfig NOT defined: use `$CODA_CONFIG/vme_<hostname>.cnf`
9. ROL loads configuration and proceeds

**Key Improvement:**
- No duplicate pedestal generation
- No duplicate config file generation
- Pedestal/config generation happens ONCE during initial setup
- ROLs use pre-generated config files
- Faster run start times

---

## Testing Recommendations

### 1. Test Default Config Fallback

**Test case: userconfig not defined**
```bash
# In CODA run control GUI, leave userconfig blank
# Start run and check ROL console output

# Expected output in VME ROL:
INFO: userconfig not defined, using default per-host config file
INFO: Using default per-host config file: /path/to/config/vme_test2.cnf

# Expected output in VTP ROL:
INFO: userconfig not defined, using default per-host VTP config file
INFO: Using default per-host VTP config: /path/to/config/vtp_test2.cnf
```

**Test case: userconfig IS defined**
```bash
# In CODA run control GUI, set userconfig to custom path
# Example: /custom/path/my_vme_config.cnf

# Expected output in VME ROL:
INFO: Using user-specified config file: /custom/path/my_vme_config.cnf

# Expected output in VTP ROL:
INFO: Using user-specified VTP config file: /custom/path/my_vtp_config.cnf
```

### 2. Test Firmware Path Resolution

**Test case: CODA_FIRMWARE set**
```bash
export CODA_FIRMWARE=/path/to/firmware
# Start run

# Expected output in VTP ROL:
INFO: Loading Z7 firmware: /path/to/firmware/fe_vtp_z7_streamingv3_ejfat_v5.bin
INFO: Z7 firmware loaded successfully
INFO: Loading V7 firmware: /path/to/firmware/fe_vtp_v7_fadc_streamingv3_ejfat.bin
INFO: V7 firmware loaded successfully
```

**Test case: CODA_FIRMWARE not set (fallback)**
```bash
unset CODA_FIRMWARE
export CODA=/site/coda/3.10_devel
# Start run

# Expected output in VTP ROL:
INFO: CODA_FIRMWARE not set, using fallback: /site/coda/3.10_devel/firmware
INFO: Loading Z7 firmware: /site/coda/3.10_devel/firmware/fe_vtp_z7_streamingv3_ejfat_v5.bin
INFO: Z7 firmware loaded successfully
```

**Test case: Neither variable set (error)**
```bash
unset CODA_FIRMWARE
unset CODA
# Start run

# Expected output in VTP ROL:
ERROR: Neither CODA_FIRMWARE nor CODA env vars are set
```

### 3. Test Missing Config Files

**Test case: Default config file missing**
```bash
# Remove default config file
rm $CODA_CONFIG/vme_test2.cnf
# Start run with userconfig not defined

# Expected output in VME ROL:
INFO: Using default per-host config file: /path/to/config/vme_test2.cnf
ERROR: Reading FADC250 Config file '/path/to/config/vme_test2.cnf' FAILED
```

### 4. Test Missing Firmware Files

**Test case: Firmware file missing**
```bash
# Remove firmware file
rm $CODA_FIRMWARE/fe_vtp_z7_streamingv3_ejfat_v5.bin
# Start run

# Expected output in VTP ROL:
INFO: Loading Z7 firmware: /path/to/firmware/fe_vtp_z7_streamingv3_ejfat_v5.bin
ERROR: Z7 firmware file not found or not readable: /path/to/firmware/fe_vtp_z7_streamingv3_ejfat_v5.bin
ERROR: Check CODA_FIRMWARE environment variable and firmware file
```

---

## Migration Guide

### For Operators

**Before Stage 3:**
- Each run regenerated pedestals and config files
- Slower run start times due to duplicate processing

**After Stage 3:**
- Config files generated ONCE during initial setup via startCoda
- ROLs use pre-generated config files
- Faster run start times

**Required Actions:**
1. Run `startCoda --file components.txt --config <name>` at least once to generate config files
2. Ensure `$CODA_CONFIG` contains:
   - `vme_<hostname>.cnf` for each VME ROC
   - `vtp_<hostname>.cnf` for each VTP ROC
3. Ensure `$CODA_FIRMWARE` contains required firmware files (or use `$CODA/firmware`)
4. In CODA run control GUI:
   - Leave userconfig blank to use defaults
   - OR set userconfig to custom path for special configurations

### For Developers

**Key Code Changes:**

**VME ROL rocDownload():**
- Removed: `parse_user_config()`, fork/exec of fadc250peds, `generate_vme_config()`, `generate_vtp_config()`
- Added: Config file selection based on `rol->usrConfig` presence
- Variable renamed: `generated_vme_config` → `fadc_config_file`

**VTP ROL rocDownload():**
- Changed: Firmware paths use `$CODA_FIRMWARE` instead of hardcoded `$CODA/src/vtp/firmware/`
- Added: `access()` checks before firmware loading
- Added: Fallback to `$CODA/firmware` if `CODA_FIRMWARE` not set

**VTP ROL rocPrestart():**
- Added: Config file selection based on `rol->usrConfig` presence
- Uses: `vtp_get_generated_config_path()` to construct default path

---

## Assumptions Made

1. **Config files are pre-generated**: The startCoda Stage 2 implementation (or equivalent process) has already created the default config files before the ROL runs

2. **Hostname stability**: The hostname returned by `get_sanitized_hostname()` matches the hostname used during config file generation

3. **Environment variables set**: CODA_CONFIG is always set in the ROL execution environment

4. **Firmware file naming**: VTP firmware filenames are defined in the ROL code and match actual files in `$CODA_FIRMWARE`

5. **Backward compatibility**: Existing runs that define userconfig in CODA GUI continue to work without modification

6. **No dynamic pedestal updates**: Pedestals are not regenerated on every run start; they are loaded from pre-generated config files

7. **Single config per host**: Each physical host has one default VME config and one default VTP config

---

## Benefits of Stage 3 Changes

1. **Performance**: Eliminates duplicate pedestal generation and config file creation
2. **Simplicity**: ROL code is simpler with no fork/exec or file generation logic
3. **Reliability**: Pre-generated configs are validated during initial setup
4. **Flexibility**: Operators can still use custom configs via userconfig parameter
5. **Maintainability**: Config generation logic exists in ONE place (startCoda) instead of duplicated in ROL
6. **Debugging**: Easier to troubleshoot - config files can be inspected before runs
7. **Version Control**: Config files can be committed to repository for reproducibility

---

## Files Modified

**rol/vme_rol/fadc_vme.c:**
- Removed: ~187 lines of pedestal/config generation code
- Added: ~30 lines of config file selection logic
- Net change: ~157 lines removed

**rol/vtp_rol/vtp_sro_1udp.c:**
- Modified: Firmware path resolution in rocDownload()
- Added: Config file selection in rocPrestart()
- Net change: ~60 lines added/modified

---

## Related Documentation

- **coda_scripts/README.md**: Complete startCoda documentation including Stage 2 config generation
- **coda_scripts/STAGE2_CHANGES.md**: Details on config file generation implementation
- **coda_scripts/EMAIL_SUMMARY.txt**: Team communication about Stages 1-2

---

**Last Updated:** February 2026
**Stage:** 3 - Move Config/Pedestal to ROL Code
