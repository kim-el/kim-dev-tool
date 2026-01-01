#!/bin/bash
# ==============================================================================
# KIM_DEV_TOOL: Apple Silicon Truth Monitor
# 
# A no-nonsense monitoring tool that shows what Activity Monitor hides:
# - Combined Power (CPU + GPU + ANE)
# - Memory Pressure (the real SSD health indicator)
# - Thermal State (explains throttling)
# - Wakeups (the silent battery killer)
#
# USAGE: sudo ./kim_dev_tool.sh
# ==============================================================================

# Strict mode (disabled due to grep edge cases)
# set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
SAMPLE_TIME=1000  # Sample window in ms
TMP_FILE="/tmp/kim_dev_tool_$$"

# Rolling average buffer (10 minutes = 600 samples at 1sec each)
POWER_HISTORY_FILE="/tmp/kim_power_history"
MAX_HISTORY_SAMPLES=600  # 10 minutes at 1 sample/sec

# ==============================================================================
# CLEANUP & SAFETY
# ==============================================================================
cleanup() {
    rm -f "$TMP_FILE"
    rm -f "$POWER_HISTORY_FILE"
    echo ""
    echo "✨ Stopped."
    exit 0
}
trap cleanup INT TERM

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Error: Requires root access for powermetrics."
    echo "   Run: sudo $0"
    exit 1
fi

# macOS check
if ! command -v powermetrics &> /dev/null; then
    echo "❌ Error: powermetrics not found. This tool requires macOS."
    exit 1
fi

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Safe integer extraction (returns 0 if invalid)
to_int() {
    local val="${1:-0}"
    # Remove any non-numeric characters except dots, then truncate to integer
    val=$(echo "$val" | sed 's/[^0-9.]//g')
    printf "%.0f" "${val:-0}" 2>/dev/null || echo "0"
}

# Extract power value from powermetrics output
extract_power() {
    local pattern="$1"
    local file="${2:-$TMP_FILE}"
    grep -E "^${pattern}" "$file" 2>/dev/null | head -1 | awk -F': ' '{print $2}' | sed 's/[^0-9.]//g'
}

# Get memory pressure state (calculated from available memory)
get_memory_pressure() {
    local output total_pages free_pages inactive_pages purgeable_pages available_pct
    output=$(memory_pressure 2>/dev/null) || { echo "Unknown|0"; return; }
    
    # Extract page counts
    total_pages=$(echo "$output" | grep -o "[0-9]* pages" | head -1 | awk '{print $1}')
    free_pages=$(echo "$output" | grep "Pages free:" | awk '{print $NF}')
    inactive_pages=$(echo "$output" | grep "Pages inactive:" | awk '{print $NF}')
    purgeable_pages=$(echo "$output" | grep "Pages purgeable:" | awk '{print $NF}')
    
    # Default to 0 if not found
    free_pages=${free_pages:-0}
    inactive_pages=${inactive_pages:-0}
    purgeable_pages=${purgeable_pages:-0}
    
    if [ -z "$total_pages" ] || [ "$total_pages" -eq 0 ]; then
        echo "Unknown|0"
        return
    fi
    
    # Available = free + inactive + purgeable (reclaimable memory)
    local available=$((free_pages + inactive_pages + purgeable_pages))
    available_pct=$((available * 100 / total_pages))
    
    if [ "$available_pct" -gt 30 ]; then
        echo "Normal|$available_pct"
    elif [ "$available_pct" -gt 15 ]; then
        echo "Warning|$available_pct"
    else
        echo "Critical|$available_pct"
    fi
}

# Get thermal state from powermetrics and actual CPU temperature
get_thermal() {
    local pressure temp_c script_dir
    pressure=$(grep -E "Current pressure level:" "$TMP_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' \t\r\n')
    
    # Get actual CPU temperature using our standalone kim_temp_bin
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -x "$script_dir/kim_temp_bin" ]; then
        temp_c=$("$script_dir/kim_temp_bin" cpu 2>/dev/null)
        if [ -n "$temp_c" ] && [ "$temp_c" != "N/A" ]; then
            temp_c=$(printf "%.0f" "$temp_c")°C
        else
            temp_c=""
        fi
    else
        temp_c=""
    fi
    
    if [ -z "$pressure" ]; then
        pressure="N/A"
    fi
    
    # Combine pressure and temperature
    if [ -n "$temp_c" ]; then
        echo "$pressure ($temp_c)"
    else
        echo "$pressure"
    fi
}

# ==============================================================================
# BASELINE CAPTURE
# ==============================================================================
clear
echo "========================================================================"
echo "           🔬 KIM_DEV_TOOL: Apple Silicon Truth Monitor"
echo "========================================================================"
echo "⚖️  Capturing baseline (idle state)..."

# Capture initial sample with all relevant samplers
if ! powermetrics -i 500 -n 1 --samplers tasks,cpu_power,gpu_power,ane_power,thermal 2>/dev/null > "$TMP_FILE"; then
    echo "❌ Error: Failed to run powermetrics. Check system permissions."
    cleanup
fi

base_watts=$(extract_power "Combined Power|System Power|Package Power")
base_watts=$(to_int "$base_watts")

echo "✓ Baseline Power: ${base_watts} mW"
echo ""
sleep 0.5

# ==============================================================================
# MAIN MONITORING LOOP (STREAM MODE)
# ==============================================================================

# Ensure kim_temp_bin exists
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -x "$script_dir/kim_temp_bin" ]; then
    echo "❌ Error: kim_temp_bin not found. Please compile it first."
    exit 1
fi

# Run the stream and pipe it into our loop
# This avoids restarting processes every second
sudo "$script_dir/kim_temp_bin" stream | while IFS= read -r line; do
    # Skip non-JSON lines (startup messages)
    if [[ ! "$line" =~ ^\{ ]]; then
        continue
    fi

    # Parse JSON into variables using jq
    # We extract everything in one go for performance
    eval $(echo "$line" | jq -r '
        @sh "cpu_temp=\(.cpu_temp) gpu_temp=\(.gpu_temp) mem_temp=\(.mem_temp) ssd_temp=\(.ssd_temp) bat_temp=\(.bat_temp) power_w=\(.power_w) bat_power_w=\(.bat_power_w) cpu_mw=\(.cpu_mw) gpu_mw=\(.gpu_mw) ane_mw=\(.ane_mw) battery_pct=\(.battery_pct) charging=\(.charging) mem_free_pct=\(.mem_free_pct) efficiency_hrs=\(.efficiency_hrs) wakeups_per_sec=\(.wakeups_per_sec)"
    ')

    # RENDER UI (cursor home)
    printf "\033[H"
    echo "========================================================================"
    echo "           🔬 KIM_DEV_TOOL: Apple Silicon Truth Monitor"
    echo "========================================================================"
    
    # Use Battery Rail Power if available (more accurate), otherwise fallback to System Power
    if [ "$bat_power_w" != "0.00" ] && [ "$bat_power_w" != "null" ]; then
        real_total_w="$bat_power_w"
    else
        real_total_w="$power_w"
    fi

    # --- BATTERY SECTION ---
    if [ "$charging" = "true" ]; then
        is_charging="yes"
    else
        is_charging="no"
    fi

    # Re-calculate efficiency using the better power number
    # Battery Wh is approx 52Wh (MBA) to 70Wh (MBP 14) to 100Wh (MBP 16)
    # We use a safe average of 60Wh if we can't get it, or trust the tool's eff_hrs if power matches
    # Since we have better power now, let's just do:
    if [ $(echo "$real_total_w > 0.5" | bc -l) -eq 1 ]; then
        # Use the efficiency_hrs from tool but scale it if the tool used PSTR instead of PPBR
        # Actually, let's just trust the tool's efficiency_hrs if it was updated to use PPBR?
        # My Rust change didn't update the efficiency calculation in Rust to use PPBR.
        # So I should recalculate it here.
        # Let's assume ~60Wh capacity for now as a baseline or 52Wh for Air.
        # Better: The tool sends efficiency_hrs based on PSTR.
        # Recalc: new_eff = old_eff * (PSTR / PPBR)
        avg_100_hours=$(echo "$efficiency_hrs * $power_w / $real_total_w" | bc -l)
    else
        avg_100_hours="99.9"
    fi
    
    # Calculate Time Left
    if [ $(echo "$real_total_w > 0" | bc -l) -eq 1 ]; then
        time_left_hrs=$(echo "$avg_100_hours * $battery_pct / 100" | bc -l)
        hrs_int=$(echo "$time_left_hrs" | awk '{print int($1)}')
        mins_int=$(echo "($time_left_hrs - $hrs_int) * 60" | bc -l | awk '{print int($1)}')
        time_remaining=$(printf "%d:%02d" "$hrs_int" "$mins_int")
    else
        time_remaining="--:--"
    fi

    printf "🔋 BATTERY:    %3d%%   " "$battery_pct"
    if [ "$is_charging" = "yes" ]; then
        printf "\033[32m(Charging)\033[0m\033[K\n"
    elif [ $(echo "$avg_100_hours >= 12" | bc -l) -eq 1 ]; then
        printf "(@100%%: %.1fh) ✅\033[K\n" "$avg_100_hours"
    elif [ $(echo "$avg_100_hours >= 6" | bc -l) -eq 1 ]; then
        printf "\033[33m(@100%%: %.1fh)\033[0m\033[K\n" "$avg_100_hours"
    else
        printf "\033[31m(@100%%: %.1fh - heavy!)\033[0m\033[K\n" "$avg_100_hours"
    fi
    printf "   ├─ Power Draw:  %s W\033[K\n" "$real_total_w"
    printf "   ├─ Time Left:   %s (est)\033[K\n" "$time_remaining"
    printf "   └─ Live @100%%: %.1fh\033[K\n" "$avg_100_hours"
    
    echo ""
    
    # --- POWER SECTION ---
    total_sys_mw=$(echo "$real_total_w * 1000" | bc -l | awk '{print int($1)}')
    soc_mw=$((cpu_mw + gpu_mw + ane_mw))
    other_mw=$((total_sys_mw - soc_mw))
    [ "$other_mw" -lt 0 ] && other_mw=0
    
    printf "⚡ POWER:       %s W   (Total System)\033[K\n" "$real_total_w"
    printf "   ├─ CPU:     %5d mW\033[K\n" "$cpu_mw"
    printf "   ├─ GPU:     %5d mW\033[K\n" "$gpu_mw"
    printf "   ├─ ANE:     %5d mW\033[K\n" "$ane_mw"
    printf "   └─ Other:   %5d mW   (Display, SSD, WiFi, etc)\033[K\n" "$other_mw"
    
    echo ""
    
    # --- THERMAL SECTION ---
    # Find hottest
    hottest_temp=$cpu_temp # Simple default
    if [ $(echo "$gpu_temp > $hottest_temp" | bc -l) -eq 1 ]; then hottest_temp=$gpu_temp; fi
    
    printf "🌡️  THERMAL:    "
    if [ $(echo "$hottest_temp < 60" | bc -l) -eq 1 ]; then
        printf "\033[32m%.1f°C\033[0m   (Target: <60°C) ✅\033[K\n" "$hottest_temp"
    elif [ $(echo "$hottest_temp < 80" | bc -l) -eq 1 ]; then
        printf "\033[33m%.1f°C\033[0m   (Target: <60°C)\033[K\n" "$hottest_temp"
    else
        printf "\033[31m%.1f°C\033[0m   (Target: <60°C - Throttling!)\033[K\n" "$hottest_temp"
    fi
    
    printf "   ├─ CPU:      %6.1f°C\033[K\n" "$cpu_temp"
    printf "   ├─ GPU:      %6.1f°C\033[K\n" "$gpu_temp"
    printf "   ├─ Memory:   %6.1f°C\033[K\n" "$mem_temp"
    printf "   ├─ SSD:      %6.1f°C\033[K\n" "$ssd_temp"
    printf "   └─ Battery:  %6.1f°C\033[K\n" "$bat_temp"
    
    echo ""
    
    # --- MEMORY SECTION ---
    printf "🧠 MEMORY:     %d%% free   " "$mem_free_pct"
    if [ "$mem_free_pct" -gt 30 ]; then
        printf "(Target: >30%%) ✅\033[K\n"
    elif [ "$mem_free_pct" -gt 15 ]; then
        printf "\033[33m(Target: >30%%)\033[0m\033[K\n"
    else
        printf "\033[31m(Target: >30%%)\033[0m\033[K\n"
    fi
    
    # --- WAKEUPS SECTION ---
    printf "💤 WAKEUPS:    %5d/s   " "$wakeups_per_sec"
    if [ "$wakeups_per_sec" -lt 500 ]; then
        printf "(Target: <500/s) ✅\033[K\n"
    elif [ "$wakeups_per_sec" -lt 1000 ]; then
        printf "\033[33m(Target: <500/s)\033[0m\033[K\n"
    else
        printf "\033[31m(Target: <500/s)\033[0m\033[K\n"
    fi
    
    echo ""
    echo "------------------------------------------------------------------------"
    printf "%-35s | %10s | %10s\033[K\n" "TOP PROCESSES (Updates every 5s)" "CPU ms/s" "WAKEUPS"
    echo "------------------------------------------------------------------------"
    
    # Parse top_cpu JSON array
    echo "$line" | jq -r '.top_cpu[] | "\(.name)|\(.cpu_ms)|\(.wakeups)"' | while IFS='|' read -r name cpu wkp; do
        # Friendly Name Logic (Copied from original)
        case "$name" in
            *WindowServer*) friendly_name="macOS Display" ;;
            *kernel_task*) friendly_name="macOS Kernel" ;;
            *mdworker*|*mds*|*mds_stores*) friendly_name="Spotlight Search" ;;
            *backupd*) friendly_name="Time Machine" ;;
            *softwareupdated*) friendly_name="Software Update" ;;
            *cloudd*) friendly_name="iCloud Sync" ;;
            *photolibraryd*) friendly_name="Photos Library" ;;
            *AMPDeviceDiscovery*|*AMPLibrary*) friendly_name="Apple Music" ;;
            *sysmond*) friendly_name="System Monitor" ;;
            *contextstored*) friendly_name="Context Store" ;;
            *bluetoothd*) friendly_name="Bluetooth" ;;
            *PerfPowerServices*) friendly_name="Power Manager" ;;
            *coreaudiod*) friendly_name="Core Audio" ;;
            *hidd*) friendly_name="HID (Input)" ;;
            *powerd*) friendly_name="Power Daemon" ;;
            *launchd*) friendly_name="Launch Daemon" ;;
            *configd*) friendly_name="System Config" ;;
            *diskarbitrationd*) friendly_name="Disk Manager" ;;
            *fseventsd*) friendly_name="File Events" ;;
            *notifyd*) friendly_name="Notifications" ;;
            *usbd*) friendly_name="USB Daemon" ;;
            *airportd*) friendly_name="WiFi Daemon" ;;
            *logd*) friendly_name="System Logger" ;;
            *securityd*) friendly_name="Security Daemon" ;;
            *trustd*) friendly_name="Trust Daemon" ;;
            *nsurlsessiond*) friendly_name="URL Session" ;;
            *symptomsd*) friendly_name="Diagnostics" ;;
            *apsd*) friendly_name="Apple Push" ;;
            *) friendly_name="$name" ;;
        esac
        
        name_short=$(printf "%.33s" "$friendly_name")
        
        # Color based on CPU usage
        if [ $(echo "$cpu > 50" | bc -l) -eq 1 ]; then
            printf "\033[31m%-35s | %10.1f | %10.1f\033[0m\033[K\n" "$name_short" "$cpu" "$wkp"
        elif [ $(echo "$cpu > 20" | bc -l) -eq 1 ]; then
            printf "\033[33m%-35s | %10.1f | %10.1f\033[0m\033[K\n" "$name_short" "$cpu" "$wkp"
        else
            printf "%-35s | %10.1f | %10.1f\033[K\n" "$name_short" "$cpu" "$wkp"
        fi
    done
    
    echo "------------------------------------------------------------------------"
    
    # Battery Impact (High Wakeups)
    impact_count=$(echo "$line" | jq '.high_wakeups | length')
    if [ "$impact_count" -gt 0 ]; then
        printf "\n\033[33m🔋 BATTERY IMPACT:\033[0m Apps with high wakeups (>50/s):\033[K\n"
        echo "$line" | jq -r '.high_wakeups[] | "\(.name) (\(.wakeups)/s)"' | head -3 | while read -r row; do
            printf "   ⚠️  %s\033[K\n" "$row"
        done
        printf "   \033[2m→ These apps prevent deep sleep and drain battery faster\033[0m\033[K\n"
    else
         # Clear previous lines if no impact
         printf "\033[K\n\033[K\n\033[K\n"
    fi

    echo "------------------------------------------------------------------------"
    printf "⏱️  Power/Temps: 1s (SMC) | Processes: 5s (Low Observer Effect)\033[K\n"
    
done
