# Seagate Drive SMART Manipulation Detection

A bash script to detect potential SMART data manipulation on Seagate enterprise drives. This tool is particularly useful for verifying the authenticity of refurbished or second-hand drives by comparing SMART attributes with tamper-resistant FARM (Field Accessible Reliability Metrics) data.

## Overview

When purchasing refurbished drives, sellers may reset SMART data to make heavily-used drives appear new. This script detects such manipulation by comparing:

- **SMART Power On Hours** (can be reset with third-party tools)
- **FARM Power On Hours** (hardware-protected, cannot be reset)

If these values differ significantly, the drive has likely been tampered with.

## How It Works

The script uses Seagate's FARM technology, which stores reliability metrics in tamper-resistant firmware. Unlike standard SMART attributes, FARM data cannot be reset or modified by software tools.

**Detection Method:**
1. Reads SMART Power On Hours (attribute 9)
2. Reads FARM Power On Hours from firmware
3. Compares the two values
4. Flags drives with discrepancies >100 hours as manipulated

Additionally checks:
- Assembly date vs. power-on hours (old assembly but low hours = suspicious)
- Spindle hours and head flight hours for consistency
- Power cycle counts and temperature history

## Requirements

- **Operating System:** Linux (tested on Debian/Ubuntu)
- **Privileges:** Root access (sudo)
- **Tool:** `smartctl` version 7.4 or higher (for FARM support)
- **Hardware:** Seagate enterprise drives with FARM support

### Supported Drives

Only Seagate **enterprise** drives support FARM data:

✅ **Supported:**
- Seagate Exos series (e.g., ST16000NM000J)
- IronWolf Pro series
- SkyHawk AI series

❌ **Not Supported:**
- Consumer/desktop drives (BarraCuda)
- Laptop drives (Mobile HDD)
- Non-Seagate drives (WD, Toshiba, etc.)

## Installation

### 1. Install smartmontools

**Debian/Ubuntu:**
```bash
# For Debian Bookworm or later
sudo apt install -t bookworm-backports smartmontools

# Or for Ubuntu 22.04+
sudo apt install smartmontools
```

**Other distributions:**
```bash
# RHEL/CentOS/Fedora
sudo dnf install smartmontools

# Arch Linux
sudo pacman -S smartmontools
```

### 2. Verify smartctl version

```bash
smartctl -V
```

Ensure version is 7.4 or higher for full FARM support.

### 3. Download the script

```bash
wget https://raw.githubusercontent.com/SleepyYui/check-segate-drive-smart-manipulation/main/check_drive.sh
chmod +x check_drive.sh
```

## Usage

Run the script with root privileges:

```bash
sudo ./check_drive.sh
```

The script will automatically:
1. Detect all connected drives
2. Identify Seagate enterprise drives
3. Read SMART and FARM data
4. Report manipulation status

### Example Output

**Legitimate Drive:**
```
==========================================
Checking: /dev/sda
==========================================
Model: ST16000NM000J
Serial: ABC12345
✓ Enterprise Seagate drive detected

Power On Hours Comparison:
  SMART POH:        12345 hours
  FARM POH:         12350 hours
  FARM Spindle:     12340 hours
  FARM Head Flight: 12338 hours

✓ Values match - drive appears legitimate

Additional Metrics:
  Assembly Date:    2312 (YYWW format)
  Power Cycles:     156
  Max Temperature:  42°C
```

**Manipulated Drive:**
```
==========================================
Checking: /dev/sdb
==========================================
Model: ST16000NM000J
Serial: XYZ67890
✓ Enterprise Seagate drive detected

Power On Hours Comparison:
  SMART POH:        150 hours
  FARM POH:         28450 hours
  FARM Spindle:     28440 hours
  FARM Head Flight: 28438 hours

🚨 MANIPULATION DETECTED!
   Difference: 28300 hours
   The SMART value has likely been reset!

Additional Metrics:
  Assembly Date:    2205 (YYWW format)
  Power Cycles:     892
  Max Temperature:  58°C

⚠ WARNING: Old assembly date (2205) but low hours (150)
   This may indicate SMART manipulation
```

## Interpreting Results

### Status Indicators

- **✓ Values match** - Drive appears legitimate (difference <10 hours)
- **⚠ Small discrepancy** - Difference 10-100 hours (usually normal due to spindle-down time)
- **🚨 MANIPULATION DETECTED** - Difference >100 hours (SMART data likely reset)
- **⊘ Not a Seagate drive** - Skipped (no FARM data available)
- **⊘ Consumer drive** - Skipped (FARM only on enterprise models)

### Red Flags

1. **Large POH difference** (>100 hours) - Strong indication of manipulation
2. **Old assembly date + low hours** - e.g., manufactured in 2020 but only 50 hours
3. **High power cycles but low hours** - Inconsistent usage pattern
4. **High max temperature** - May indicate hard usage despite low hours

## Troubleshooting

### "Please run as root"
```bash
sudo ./check_drive.sh
```

### "smartctl 7.4+ recommended for FARM data"
Your smartctl version is too old. Update using:
```bash
sudo apt install -t bookworm-backports smartmontools
```

### "No FARM data available"
- Verify the drive is a Seagate **enterprise** model (Exos, IronWolf Pro, SkyHawk AI)
- Consumer drives (BarraCuda, laptop drives) do not support FARM
- Some very old enterprise drives may not have FARM

### "No drives found"
- Ensure drives are connected and recognized by the system
- Check `lsblk` or `fdisk -l` to verify drive paths
- Try running `sudo smartctl --scan` to see what smartctl detects

## Limitations

- Only works with Seagate enterprise drives (FARM support required)
- Requires smartctl 7.4+ for full functionality
- FARM data may not be available on very old drives
- Small discrepancies (10-100 hours) are normal and not indicative of manipulation

## Disclaimer

This tool is provided as-is for educational and verification purposes. While FARM data is significantly more difficult to manipulate than standard SMART attributes, no detection method is 100% foolproof. Always:

- Purchase drives from reputable sellers
- Verify warranty status independently
- Run extended SMART tests before use
- Maintain backups of important data

## License

This project is open source and available for free use. No warranty is provided.

## Contributing

Contributions, bug reports, and suggestions are welcome! Please open an issue or pull request on GitHub.

## Credits

Created by SleepyYui using Claude 4.5 for verifying refurbished drive authenticity.
