# startCoda - CODA Component Launcher

## Overview

`startCoda` is a flexible script for launching CODA (CEBAF Online Data Acquisition) components with support for file-based configuration and automatic configuration file generation.

## Features

### File-Based Component Launching
- Launch multiple CODA components from a simple text file
- Support for all component types: ROC, FPGA, TS, PEB, SEB, ER, DC, PAGG
- Environment variable resolution in file paths
- Backward compatible with original startCoda behavior

### Automatic Configuration Generation
- Generates per-host VME and VTP configuration files
- Parses base configuration and combines with generated pedestal data
- Automatically computes VTP_PAYLOAD_EN from FADC slot configuration
- Intelligent file-closure detection prevents reading incomplete files

### ROC Component Features
- Automatic pedestal generation via fadc250peds
- Xterm windows remain open for user interaction
- Remote execution with proper environment setup
- Session logging to coda_tmp_log/

## Installation

No installation required. The script uses the existing CODA environment:

```bash
# Ensure CODA environment is set up
source ${CODA_SCRIPTS}/setupCODA3.bash

# Make script executable (if needed)
chmod +x ${CODA_SCRIPTS}/startCoda
```

## Usage

### Basic Syntax

```bash
startCoda --file <component_file> [--config] [-h|--help]
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `--file <path>` | **YES** | Path to component definition file. Supports environment variables. |
| `--config` | No | Enable pedestal measurement and config file generation. Takes NO parameters. |
| `-h, --help` | No | Display help message and exit. |

## Usage Examples

### 1. File-Based Launch (No Config Generation)

Launch components from a file without generating configuration files:

```bash
./startCoda --file /path/to/components.txt
```

This will:
- Launch all components defined in the file
- NOT run pedestal measurement
- NOT generate configuration files
- Output: "Config generation: DISABLED"

### 2. File-Based Launch with Config Generation

Launch components AND generate configuration files:

```bash
./startCoda --file components.txt --config
```

This will:
1. Launch all components defined in the file
2. Run pedestal measurement for ROC components
3. Wait for pedestal files to be generated
4. Create `vme_<hostname>.cnf` for each ROC host (using base.cnf + pedestals)
5. Create `vtp_<hostname>.cnf` for each ROC host (using base.cnf + computed VTP_PAYLOAD_EN)
6. Output: "Config generation: ENABLED (pedestal measurement + VME/VTP config files)"

### 3. Using Environment Variables

```bash
# Set up environment
export CODA_SCRIPTS=/path/to/coda_scripts
export CODA_CONFIG=/path/to/config

# Launch using environment variables in path
./startCoda --file $CODA_SCRIPTS/config/hallB/components.txt --config
```

### 4. Using Relative Paths

```bash
cd $CODA_SCRIPTS
./startCoda --file ./test_components.txt --config
```

### 5. Invalid Usage (Will Fail)

Running without `--file` is **not allowed**:

```bash
./startCoda
# Error: --file is required to start CODA.
# Exit code: 1
```

## Component File Format

### Structure

Component files are plain text with space-separated fields:

```
hostname  component_type  component_name  [optional_parameters]
```

### Example Component File

```bash
# CODA Component Table for Hall B
# hostname   type    name      options

# Primary Event Builders
clondaq3    PEB     PEB1
clondaq3    PAGG    PAGG1

# ROC Components (with verbose output)
test2       ROC     ROC1      -v
test2vme    ROC     ROC2      -v -i

# FPGA/VTP Components
test2vtp    FPGA    FPGA1     -v
adccal1     FPGA    FPGA2     -v

# Event Recorders
clondaq4    ER      ER1

# Commented out (not launched)
#testhost   SEB     SEB1
```

### Parsing Rules

- **Comments**: Lines starting with `#` (after optional whitespace) are ignored
- **Blank lines**: Empty lines are skipped
- **Minimum fields**: Each line must have at least 3 fields (hostname, type, name)
- **Optional parameters**: Everything after the 3rd field is passed as arguments
- **Whitespace**: Leading/trailing whitespace is trimmed

### Component Types

| Type | Description | Color |
|------|-------------|-------|
| ROC | Readout Controller | Light Green |
| FPGA | FPGA/VTP Module | Light Green |
| TS | Trigger Supervisor | Yellow |
| PEB | Primary Event Builder | Light Blue |
| SEB | Secondary Event Builder | Orange |
| ER | Event Recorder | Tan |
| DC | Data Concentrator | Grey |
| PAGG | Partial Aggregator | Light Blue |

## Configuration File Generation

### When Does It Happen?

Configuration files are generated automatically when BOTH conditions are met:
1. `--config` parameter is specified
2. At least one ROC component is defined in the component file

### Generated Files

For each ROC hostname, two files are created in `${CODA_SCRIPTS}/../config/`:

#### 1. vme_<hostname>.cnf

Contains:
- VME configuration section from base.cnf
- Appended pedestal data from `${hostname}.peds`

Example: `vme_test2.cnf`

#### 2. vtp_<hostname>.cnf

Contains:
- VTP configuration section from base.cnf
- MAC address for the host (from base.cnf mapping table)
- IP address for the host (from base.cnf mapping table)
- Computed `VTP_PAYLOAD_EN` based on FADC slots

Example: `vtp_test2.cnf`

### VTP_PAYLOAD_EN Computation

The payload enable bits are automatically calculated from the FADC slots found in the pedestal file.

**Slot-to-Payload Mapping:**
```
Slot:     10  13   9  14   8  15   7  16   6  17   5  18   4  19   3  20
Payload:   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
```

**Example:**
- If `hostname.peds` contains slots: 3, 4, 19
- Payload indices are: 14, 12, 13 (0-indexed: 14, 12, 13)
- Result: `VTP_PAYLOAD_EN 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 0`

### File Closure Detection

To ensure pedestal files are fully written before processing:
- Waits up to 60 seconds for file to appear
- Monitors file size every second
- Requires 3 consecutive identical size readings
- Prevents reading incomplete data

### Base Configuration Requirements

The `base.cnf` file must contain:

1. **VME Configuration Section** (lines 1 to VTP header)
2. **VTP Configuration Section** (VTP header to MAC/IP table)
3. **MAC/IP Mapping Table** at the end:

```bash
######################################
# VTP rocs, their MAC and IP addresses
######################################
test2    "0xCE 0xBA 0xF0 0x03 0x00 0x9d"  "129  57  69 14"
adccal1  "0xCE 0xBA 0xE1 0x01 0x02 0x03"  "129  57  68 58"
```

Format:
- MAC: Space-separated hex bytes with 0x prefix
- IP: Space-separated decimal octets

## ROC Component Behavior

### Execution Flow

When a ROC component is launched:

1. **Xterm Window Opens** with title: `hostname : ROC : component_name`
2. **SSH Connection** to the specified hostname
3. **Directory Change** to `$CODA/linuxvme/fadc-peds`
4. **Pedestal Generation** via `./fadc250peds $CODA_CONFIG/hostname.peds`
5. **Interactive Shell** after completion
6. **Log Output** saved to `coda_tmp_log/hostname_componentname_lastsession.log`

### Xterm Persistence

ROC xterm windows stay open after the pedestal program completes:
- Press Enter to return to interactive bash shell
- Window remains open for inspection/debugging
- SIGINT (Ctrl+C) is trapped and ignored

### Example ROC Session

```
****************************************
* SSHing to test2
****************************************
Fri Feb 21 12:00:00 EST 2026

[fadc250peds output...]
Pedestal calibration complete
Writing to /path/to/config/test2.peds

--- Press Enter to return to shell ---
[user presses Enter]
bash-4.2$
```

## Output and Logging

### Console Output

```
************************************************************
Starting CODA components from file: /path/to/components.txt
Using configuration: myconfig
************************************************************
Launching: PEB PEB1 on clondaq3 (options: )
Launching: ROC ROC1 on test2 (options: -v)
Launching: FPGA FPGA2 on test2vtp (options: -v)
************************************************************
Launched 3 components
************************************************************

************************************************************
Generating configuration files for ROC hosts
************************************************************

Processing ROC host: test2
  Waiting for pedestal file: /path/to/config/test2.peds
  Pedestal file found, waiting for write completion...
  Pedestal file ready (392 bytes)
  Generating: /path/to/config/vme_test2.cnf
  Appended pedestals from: /path/to/config/test2.peds (8 lines)
  Generating: /path/to/config/vtp_test2.cnf
  Completed configuration files for: test2

************************************************************
Configuration file generation complete
************************************************************
```

### Log Files

Session logs are saved to:
```
coda_tmp_log/<hostname>_<componentname>_lastsession.log
```

Example:
```
coda_tmp_log/test2_ROC1_lastsession.log
coda_tmp_log/test2vtp_FPGA2_lastsession.log
```

## Troubleshooting

### Missing --file Argument

**Error:**
```
Error: --file is required to start CODA.
```

**Solution:**
- Always provide the `--file` argument with a path to your component file
- Example: `./startCoda --file components.txt`

### --config Parameter Warning

**Warning:**
```
WARNING: --config does not take parameters. Ignoring provided value(s).
```

**Explanation:**
- `--config` is a flag and does not accept parameters
- If you provided a value (e.g., `--config myconfig`), it will be ignored
- The script will continue normally with config generation enabled

**Solution:**
- Use `--config` without any value: `./startCoda --file components.txt --config`

### Component File Not Found

**Error:**
```
ERROR: Component file not found: /path/to/file.txt
       (Original path: $CODA_SCRIPTS/file.txt)
```

**Solution:**
- Check that the file exists
- Verify environment variables are set correctly
- Use absolute paths if environment variables are problematic

### Pedestal File Not Ready

**Warning:**
```
WARNING: Pedestal file not found after 60s: /path/to/hostname.peds
         Skipping config generation for hostname
```

**Possible Causes:**
- fadc250peds program failed or crashed
- Network connectivity issues to ROC host
- Incorrect CODA_CONFIG path
- Insufficient permissions

**Solution:**
- Check the ROC xterm window for error messages
- Verify SSH connectivity to the host
- Check $CODA_CONFIG is set correctly
- Manually run fadc250peds to debug

### MAC/IP Mapping Not Found

**Warning:**
```
WARNING: No MAC/IP mapping found for hostname: test2 in base.cnf
```

**Solution:**
Add the hostname to the MAC/IP table in base.cnf:
```bash
######################################
# VTP rocs, their MAC and IP addresses
######################################
test2 "0xCE 0xBA 0xF0 0x03 0x00 0x9d" "129  57  69 14"
```

### Invalid Line Format

**Warning:**
```
WARNING: Line 10 has fewer than 3 fields, skipping: badline incomplete
```

**Solution:**
Ensure each non-comment line has at least 3 fields:
```bash
hostname component_type component_name [options]
```

### Base.cnf Not Found

**Warning:**
```
WARNING: base.cnf not found at: /path/to/config/base.cnf
         Skipping configuration file generation
```

**Solution:**
- Ensure base.cnf exists in the config/ directory
- Check CODA_SCRIPTS environment variable
- Verify directory structure

## Environment Variables

The script uses these environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `CODA` | CODA installation directory | `/site/coda/3.10_devel` |
| `CODA_SCRIPTS` | Directory containing this script | `/path/to/coda_scripts` |
| `CODA_CONFIG` | Configuration directory for pedestal files | `/path/to/config` |
| `SESSION` | CODA session name | `session` |
| `EXPID` | Experiment ID | `hallb` |

Set these in your environment setup script (e.g., `setupCODA3.bash`).

## Testing

Test scripts are provided in the coda_scripts directory:

### Test Configuration Generation
```bash
cd $CODA_SCRIPTS
./test_config_gen.sh
```

Verifies:
- VME/VTP section extraction
- MAC/IP parsing
- Slot extraction
- VTP_PAYLOAD_EN computation
- File generation

### Test File Closure Detection
```bash
cd $CODA_SCRIPTS
./test_wait_for_peds.sh
```

Simulates slow file writing and verifies the wait logic.

### Example Component File
```bash
test_components.txt
```

A sample component file for testing.

## Advanced Usage

### Custom Component Scripts

The script uses `start<TYPE>.sh` for each component type. To customize:

1. Create a new script: `start<TYPE>.sh`
2. Place in `$CODA_SCRIPTS/`
3. Make executable: `chmod +x start<TYPE>.sh`
4. Use in component file

### Remote User Customization

By default, components SSH as the current user. To change, modify the `remote_vme` call in `launch_component()`.

### Custom Xterm Geometry

Modify these variables in the script:
```bash
XTDIM=80x19      # Width x Height
FIRST_XPOS=0     # Starting X position
FIRST_YPOS=30    # Starting Y position
XINCR=510        # X increment between columns
YINCR=280        # Y increment between rows
```

## Notes

1. **Mandatory --file**: The `--file` argument is now REQUIRED for all executions (no default behavior)
2. **--config is a Flag**: The `--config` option takes NO parameters (previously required a config name)
3. **Parallel Launch**: Components are launched sequentially with 0.5s delay between each
4. **Platform & RcGui**: Always started in file-based mode (platform in background, RcGui after 2s delay)
5. **Config Generation**: Only occurs when `--config` flag is present AND ROC components exist
6. **File Paths**: Both absolute and relative paths are supported
7. **Xterm Colors**: Each component type has a distinct color for easy identification

## See Also

- `STARTCODA_ARGUMENT_CHANGES.md` - Detailed documentation of argument parsing changes
- `STAGE2_CHANGES.md` - Config file generation implementation notes
- `STAGE3_CHANGES.md` - ROL code modifications for config handling
- `EMAIL_SUMMARY.txt` - Summary for team communication (Stages 1-2)
- `EMAIL_SUMMARY_STAGE3.txt` - Summary for team communication (Stage 3)
- `setupCODA3.bash` - Environment setup
- `coda_conf_functions` - Original component table parsing functions

## Support

For issues or questions:
1. Check this README for common solutions
2. Review test scripts for examples
3. Check log files in `coda_tmp_log/`
4. Inspect ROC xterm windows for detailed error messages

## Version History

- **Argument Changes** (Feb 2026): Made --file mandatory, --config parameterless flag
- **Stage 3** (Feb 2026): Moved config/pedestal handling to ROL code
- **Stage 2** (Feb 2026): Added automatic configuration file generation
- **Stage 1** (Feb 2026): Added file-based component launching with --file and --config parameters
- **Original**: Basic component launching via startXterms

---

**Last Updated:** February 2026
