#!/bin/bash

# Seagate Drive Manipulation Detection Script
# Only checks enterprise drives that support FARM data
# Requires smartctl 7.4+ for FARM support

echo "=========================================="
echo "Seagate Drive Manipulation Check"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: Please run as root (sudo)"
    exit 1
fi

# Check smartctl version
SMARTCTL_VERSION=$(smartctl -V 2>/dev/null | grep "smartctl" | head -1 | grep -oE '[0-9]+.[0-9]+' | head -1)
echo "smartctl version: $SMARTCTL_VERSION"

if [ -n "$SMARTCTL_VERSION" ]; then
    VERSION_CHECK=$(echo "$SMARTCTL_VERSION" | awk '{if ($1 < 7.4) print "old"; else print "ok"}')
    if [ "$VERSION_CHECK" = "old" ]; then
        echo "WARNING: smartctl 7.4+ recommended for FARM data. Found: $SMARTCTL_VERSION"
        echo "Install with: apt install -t bookworm-backports smartmontools"
    fi
fi
echo ""

# Function to check if drive supports FARM
supports_farm() {
    local MODEL=$1
    
    # Check for enterprise model patterns
    # Exos: Contains "NM" (nearline model) like ST16000NM000J
    # IronWolf Pro: Contains "VN" and ends with numbers
    # SkyHawk AI: Contains specific patterns
    
    if echo "$MODEL" | grep -qiE "ST[0-9]+NM"; then
        return 0  # Exos series
    elif echo "$MODEL" | grep -qiE "ST[0-9]+VN[0-9]+"; then
        return 0  # IronWolf Pro
    elif echo "$MODEL" | grep -qi "IronWolf Pro"; then
        return 0
    elif echo "$MODEL" | grep -qi "SkyHawk AI"; then
        return 0
    elif echo "$MODEL" | grep -qi "Exos"; then
        return 0
    fi
    
    return 1  # Consumer drive, no FARM support
}

# Function to check a single drive
check_drive() {
    local DRIVE=$1
    echo "=========================================="
    echo "Checking: $DRIVE"
    echo "=========================================="
    
    # Get basic drive info
    MODEL=$(smartctl -i $DRIVE 2>/dev/null | grep "Device Model" | awk -F: '{print $2}' | xargs)
    SERIAL=$(smartctl -i $DRIVE 2>/dev/null | grep "Serial Number" | awk -F: '{print $2}' | xargs)
    
    # Skip if not a drive or can't read SMART
    if [ -z "$MODEL" ]; then
        echo "⊘ Skipping - not accessible or not a SMART drive"
        echo ""
        return
    fi
    
    echo "Model: $MODEL"
    echo "Serial: $SERIAL"
    
    # Check if it's a Seagate drive
    IS_SEAGATE=0
    if echo "$MODEL" | grep -qi "seagate"; then
        IS_SEAGATE=1
    elif echo "$MODEL" | grep -qiE "^ST[0-9]"; then
        IS_SEAGATE=1
    fi
    
    if [ $IS_SEAGATE -eq 0 ]; then
        echo "⊘ Not a Seagate drive - skipping"
        echo ""
        return
    fi
    
    # Check if drive supports FARM
    if ! supports_farm "$MODEL"; then
        echo "⊘ Consumer/laptop drive - no FARM support (skipping)"
        echo ""
        return
    fi
    
    echo "✓ Enterprise Seagate drive detected"
    
    # Get SMART Power On Hours
    SMART_POH=$(smartctl -a $DRIVE 2>/dev/null | grep "Power_On_Hours" | awk '{print $10}')
    
    # Get FARM data (requires smartctl 7.4+)
    FARM_OUTPUT=$(smartctl -l farm $DRIVE 2>/dev/null)
    
    if echo "$FARM_OUTPUT" | grep -q "INVALID ARGUMENT"; then
        echo "⚠ Cannot read FARM data - smartctl 7.4+ required"
        echo "  SMART Power On Hours: $SMART_POH"
        echo ""
        return
    fi
    
    if [ -z "$FARM_OUTPUT" ]; then
        echo "⚠ No FARM data available for this drive"
        echo "  SMART Power On Hours: $SMART_POH"
        echo ""
        return
    fi
    
    # Extract FARM values
    FARM_POH=$(echo "$FARM_OUTPUT" | grep "Power on Hours:" | head -1 | awk -F: '{print $2}' | xargs)
    FARM_SPINDLE=$(echo "$FARM_OUTPUT" | grep "Spindle Power on Hours:" | awk -F: '{print $2}' | xargs)
    FARM_HEAD=$(echo "$FARM_OUTPUT" | grep "Head Flight Hours:" | head -1 | awk -F: '{print $2}' | xargs)
    ASSEMBLY_DATE=$(echo "$FARM_OUTPUT" | grep "Assembly Date" | awk -F: '{print $2}' | xargs)
    POWER_CYCLES=$(echo "$FARM_OUTPUT" | grep "Power Cycle Count:" | head -1 | awk -F: '{print $2}' | xargs)
    MAX_TEMP=$(echo "$FARM_OUTPUT" | grep "Highest Temperature:" | awk -F: '{print $2}' | xargs)
    
    echo ""
    echo "Power On Hours Comparison:"
    echo "  SMART POH:        $SMART_POH hours"
    echo "  FARM POH:         $FARM_POH hours"
    echo "  FARM Spindle:     $FARM_SPINDLE hours"
    echo "  FARM Head Flight: $FARM_HEAD hours"
    echo ""
    
    # Calculate difference
    if [ -n "$SMART_POH" ] && [ -n "$FARM_POH" ]; then
        DIFF=$((FARM_POH - SMART_POH))
        ABS_DIFF=${DIFF#-}
        
        # Check for manipulation (threshold: >100 hours difference)
        if [ $ABS_DIFF -gt 100 ]; then
            echo "🚨 MANIPULATION DETECTED!"
            echo "   Difference: $DIFF hours"
            echo "   The SMART value has likely been reset!"
        elif [ $ABS_DIFF -gt 10 ]; then
            echo "⚠ Small discrepancy detected ($DIFF hours)"
            echo "   This is usually normal and may be due to spindle-down time"
        else
            echo "✓ Values match - drive appears legitimate"
        fi
    fi
    
    echo ""
    echo "Additional Metrics:"
    echo "  Assembly Date:    $ASSEMBLY_DATE (YYWW format)"
    echo "  Power Cycles:     $POWER_CYCLES"
    echo "  Max Temperature:  $MAX_TEMP°C"
    
    # Check assembly date vs low hours (warns if drive older than 2 years but <100 hours)
    if [ -n "$ASSEMBLY_DATE" ] && [ -n "$SMART_POH" ]; then
        YEAR_PREFIX=${ASSEMBLY_DATE:0:2}
        if [ "$SMART_POH" -lt 100 ] && [ "$YEAR_PREFIX" -lt 24 ]; then
            echo ""
            echo "⚠ WARNING: Old assembly date ($ASSEMBLY_DATE) but low hours ($SMART_POH)"
            echo "   This may indicate SMART manipulation"
        fi
    fi
    
    echo ""
}

# Main execution
echo ""

# Scan all drives
DRIVES=$(smartctl --scan-open 2>/dev/null | grep -E '/dev/sd' | awk '{print $1}')

if [ -z "$DRIVES" ]; then
    echo "No drives found!"
    exit 1
fi

echo "Found drives to scan:"
echo "$DRIVES"
echo ""

# Check each drive
CHECKED=0
for DRIVE in $DRIVES; do
    check_drive "$DRIVE"
    # Count drives that were actually checked (not skipped)
    MODEL=$(smartctl -i $DRIVE 2>/dev/null | grep "Device Model" | awk -F: '{print $2}' | xargs)
    if [ -n "$MODEL" ] && supports_farm "$MODEL"; then
        CHECKED=$((CHECKED + 1))
    fi
done

if [ $CHECKED -eq 0 ]; then
    echo "⊘ No enterprise Seagate drives with FARM support found"
    echo "   FARM is only available on: Exos, IronWolf Pro, SkyHawk AI"
fi

echo "=========================================="
echo "Scan complete! ($CHECKED enterprise drive(s) checked)"
echo "=========================================="
