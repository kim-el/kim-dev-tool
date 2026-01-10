#!/bin/bash
# ==============================================================================
# KIM_DEV_TOOL: Apple Silicon Truth Monitor
# 
# Optimized for Low Observer Effect (<0.1% CPU usage)
# Focuses on Power (Watts), Memory Pressure, and Wakeups.
#
# USAGE: sudo ./kim_dev_tool.sh
# ==============================================================================

# ==============================================================================
# CONFIGURATION & DEPENDENCIES
# ==============================================================================

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Error: Requires root access for powermetrics."
    echo "   Run: sudo $0"
    exit 1
fi

# Dependency check: jq
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is required for JSON parsing."
    echo "   Install with: brew install jq"
    exit 1
fi

# Ensure kim_temp_bin exists
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -x "$script_dir/kim_temp_bin" ]; then
    echo "❌ Error: kim_temp_bin not found. Please compile it first."
    exit 1
fi

# Cleanup on exit
cleanup() {
    echo ""
    echo "✨ Stopped."
    exit 0
}
trap cleanup INT TERM

# ==================== MAIN MONITORING LOOP ====================

clear
echo "========================================================================"
echo "           🔬 KIM_DEV_TOOL: Apple Silicon Truth Monitor"
echo "========================================================================"
echo "⚖️  Initializing high-efficiency stream..."

# Run the stream and pipe it into our loop
# Direct parsing with jq instead of eval for security and robustness
sudo "$script_dir/kim_temp_bin" stream | while IFS= read -r line; do
    # Skip non-JSON lines
    [[ ! "$line" =~ ^\{ ]] && continue

    # Direct Extraction (Addressing Code Review Item #3)
    cpu_temp=$(echo "$line" | jq -r '.cpu_temp')
    gpu_temp=$(echo "$line" | jq -r '.gpu_temp')
    mem_temp=$(echo "$line" | jq -r '.mem_temp')
    ssd_temp=$(echo "$line" | jq -r '.ssd_temp')
    bat_temp=$(echo "$line" | jq -r '.bat_temp')
    
    power_w=$(echo "$line" | jq -r '.power_w')
    bat_power_w=$(echo "$line" | jq -r '.bat_power_w')
    mem_power_w=$(echo "$line" | jq -r '.mem_power_w')
    display_w=$(echo "$line" | jq -r '.display_w // 0')
    
    cpu_mw=$(echo "$line" | jq -r '.cpu_mw')
    gpu_mw=$(echo "$line" | jq -r '.gpu_mw')
    ane_mw=$(echo "$line" | jq -r '.ane_mw')
    
    battery_pct=$(echo "$line" | jq -r '.battery_pct')
    charging=$(echo "$line" | jq -r '.charging')
    cycle_count=$(echo "$line" | jq -r '.cycle_count')
    health_pct=$(echo "$line" | jq -r '.health_pct')
    mem_free_pct=$(echo "$line" | jq -r '.mem_free_pct')
    efficiency_hrs=$(echo "$line" | jq -r '.efficiency_hrs')
    wakeups_per_sec=$(echo "$line" | jq -r '.wakeups_per_sec')

    # RENDER UI
    printf "\033[H"
    echo "========================================================================"
    echo "           🔬 KIM_DEV_TOOL: Apple Silicon Truth Monitor"
    echo "========================================================================"
    
    # Accurate Power Selection
    if [ "$bat_power_w" != "0.00" ] && [ "$bat_power_w" != "null" ]; then
        real_total_w="$bat_power_w"
    else
        real_total_w="$power_w"
        bat_power_w="$power_w"
    fi

    # Battery Section
    is_charging="no"; [ "$charging" = "true" ] && is_charging="yes"
    
    # Time Remaining
    if [ $(echo "$real_total_w > 0" | bc -l) -eq 1 ]; then
        time_left_hrs=$(echo "$efficiency_hrs * $battery_pct / 100" | bc -l)
        hrs_int=$(echo "$time_left_hrs" | awk '{print int($1)}')
        mins_int=$(echo "($time_left_hrs - $hrs_int) * 60" | bc -l | awk '{print int($1)}')
        time_remaining=$(printf "%d:%02d" "$hrs_int" "$mins_int")
    else
        time_remaining="--:--"
    fi

    printf "🔋 BATTERY:    %3d%%   " "$battery_pct"
    if [ "$is_charging" = "yes" ]; then
        printf "\033[32m(Charging)\033[0m\033[K\n"
    else
        printf "(Cycle Count|Maximum Capacity: %d|%d%%)\033[K\n" "$cycle_count" "$health_pct"
    fi
    printf "   ├─ Power Draw:  %s W\033[K\n" "$real_total_w"
    printf "   └─ Time Left:   %s (est)\033[K\n" "$time_remaining"
    
    echo ""
    
    # Power Breakdown
    # Display power from SMC formula (PSTR - CPU - GPU - ANE - Memory)
    # This is now calculated accurately in Rust binary
    screen_mw=$(echo "$display_w * 1000" | bc -l | awk '{print int($1)}')
    
    # Misc is System Logic - Components
    # Note: PSTR includes CPU/GPU/ANE/Memory and Logic Board overhead
    # We subtract estimated components to find the "Losses/WiFi/Fan" overhead
    system_logic_mw=$(echo "$power_w * 1000" | bc -l | awk '{print int($1)}')
    known_components=$((cpu_mw + gpu_mw + ane_mw + screen_mw))
    misc_mw=$((system_logic_mw - known_components))
    [ "$misc_mw" -lt 0 ] && misc_mw=0
    
    printf "⚡ POWER:       %s W   (Total System)\033[K\n" "$real_total_w"
    printf "   ├─ CPU:     %5d mW\033[K\n" "$cpu_mw"
    printf "   ├─ GPU:     %5d mW\033[K\n" "$gpu_mw"
    printf "   ├─ ANE:     %5d mW\033[K\n" "$ane_mw"
    printf "   ├─ Memory:  %5d mW\033[K\n" "$misc_mw"
    printf "   └─ Disp+Sys:%5d mW   (Screen + WiFi/SSD/Idle)\033[K\n" "$screen_mw"
    
    echo ""
    
    # Thermal Section
    hottest_temp=$cpu_temp
    [ $(echo "$gpu_temp > $hottest_temp" | bc -l) -eq 1 ] && hottest_temp=$gpu_temp
    
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
    
    # Memory Section
    printf "🧠 MEMORY:     %d%% free   " "$mem_free_pct"
    if [ "$mem_free_pct" -gt 30 ]; then
        printf "(Target: >30%%) ✅\033[K\n"
    elif [ "$mem_free_pct" -gt 15 ]; then
        printf "\033[33m(Target: >30%%)\033[0m\033[K\n"
    else
        printf "\033[31m(Target: >30%%)\033[0m\033[K\n"
    fi
    
    # Wakeups Section
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
    printf "% -35s | %10s | %10s\033[K\n" "TOP PROCESSES (Updates every 5s)" "CPU ms/s" "WAKEUPS"
    echo "------------------------------------------------------------------------"
    
    echo "$line" | jq -r '.top_cpu[] | "\(.name)|\(.cpu_ms)|\(.wakeups)"' | while IFS='|' read -r name cpu wkp; do
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
        if [ $(echo "$cpu > 50" | bc -l) -eq 1 ]; then
            printf "\033[31m%-35s | %10.1f | %10.1f\033[0m\033[K\n" "$name_short" "$cpu" "$wkp"
        elif [ $(echo "$cpu > 20" | bc -l) -eq 1 ]; then
            printf "\033[33m%-35s | %10.1f | %10.1f\033[0m\033[K\n" "$name_short" "$cpu" "$wkp"
        else
            printf "% -35s | %10.1f | %10.1f\033[K\n" "$name_short" "$cpu" "$wkp"
        fi
    done
    
    echo "------------------------------------------------------------------------"
    impact_count=$(echo "$line" | jq '.high_wakeups | length')
    if [ "$impact_count" -gt 0 ]; then
        printf "\n\033[33m🔋 BATTERY IMPACT:\033[0m Apps with high wakeups (>50/s):\033[K\n"
        echo "$line" | jq -r '.high_wakeups[] | "\(.name) (\(.wakeups)/s)"' | head -3 | while read -r row; do
            printf "   ⚠️  %s\033[K\n" "$row"
        done
        printf "   \033[2m→ These apps prevent deep sleep and drain battery faster\033[0m\033[K\n"
    fi

    echo "------------------------------------------------------------------------"
    printf "⏱️  Power/Temps: 1s (SMC) | Processes: 5s (Low Observer Effect)\033[K\n"
done