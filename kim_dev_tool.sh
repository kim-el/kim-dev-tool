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
# MAIN MONITORING LOOP
# ==============================================================================
while true; do
    # 1. CAPTURE METRICS
    if ! powermetrics -i "$SAMPLE_TIME" -n 1 --samplers tasks,cpu_power,gpu_power,ane_power,thermal 2>/dev/null > "$TMP_FILE"; then
        echo "⚠️  Capture failed, retrying..."
        sleep 1
        continue
    fi
    
    # Validate output
    if [ ! -s "$TMP_FILE" ]; then
        echo "⚠️  Empty output, retrying..."
        sleep 1
        continue
    fi
    
    # 2. PARSE POWER METRICS
    total_watts=$(extract_power "Combined Power|System Power|Package Power")
    cpu_watts=$(extract_power "CPU Power")
    gpu_watts=$(extract_power "GPU Power")
    ane_watts=$(extract_power "ANE Power")
    
    total_watts=$(to_int "$total_watts")
    cpu_watts=$(to_int "$cpu_watts")
    gpu_watts=$(to_int "$gpu_watts")
    ane_watts=$(to_int "$ane_watts")
    
    watts_delta=$((total_watts - base_watts))
    
    # 3. PARSE E-CLUSTER / P-CLUSTER (if available)
    e_cluster=$(extract_power "E-Cluster Power")
    p_cluster=$(extract_power "P-Cluster Power")
    e_cluster=$(to_int "$e_cluster")
    p_cluster=$(to_int "$p_cluster")
    
    # 4. PARSE WAKEUPS (Column 7 = Intr wakeups, from "Wakeups (Intr, Pkg idle)")
    # Format: Name ID CPU_ms/s User% Deadlines(<2ms) Deadlines(2-5ms) Wakeups(Intr) Wakeups(PkgIdle)
    wakeups=$(awk '
        /^Name/ { in_tasks=1; next }
        /^ALL_TASKS/ { exit }
        /^CPU Power/ { exit }
        in_tasks && NF >= 8 && $2 ~ /^[0-9]+$/ {
            # $7 is Intr wakeups column
            sum += $7
        }
        END { printf "%.0f", sum+0 }
    ' "$TMP_FILE")
    wakeups="${wakeups:-0}"
    
    # 5. MEMORY PRESSURE
    mem_info=$(get_memory_pressure)
    mem_state=$(echo "$mem_info" | cut -d'|' -f1)
    mem_pct=$(echo "$mem_info" | cut -d'|' -f2)
    
    # 6. THERMAL
    thermal=$(get_thermal)
    
    # 7. RENDER UI (cursor home - overwrite in place for smooth updates)
    printf "\033[H"  # Move cursor to top-left, overwrite existing content
    echo "========================================================================"
    echo "           🔬 KIM_DEV_TOOL: Apple Silicon Truth Monitor"
    echo "========================================================================"
    
    # Get script directory and real system power for calculations
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -x "$script_dir/kim_temp_bin" ]; then
        real_power_w=$("$script_dir/kim_temp_bin" power 2>/dev/null)
    else
        real_power_w=""
    fi
    
    # ==================== BATTERY SECTION (TOP) ====================
    battery_info=$(pmset -g batt 2>/dev/null)
    battery_pct=$(echo "$battery_info" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
    battery_pct=${battery_pct:-0}
    time_remaining=$(echo "$battery_info" | grep -oE '[0-9]+:[0-9]+' | head -1)
    time_remaining=${time_remaining:-"--:--"}
    # More robust charging detection - look for "; charging;" pattern
    if echo "$battery_info" | grep -q "; charging;"; then
        is_charging="yes"
    elif echo "$battery_info" | grep -q "AC Power"; then
        # On AC but might be "charged" or "finishing charge"
        if echo "$battery_info" | grep -q "charged\|finishing"; then
            is_charging="no"
        else
            is_charging="yes"
        fi
    else
        is_charging="no"
    fi
    
    # Calculate @100% hours (efficiency metric)
    # Get battery design capacity dynamically (works for all Mac models)
    battery_mah=$(ioreg -r -c AppleSmartBattery 2>/dev/null | grep -oE '"DesignCapacity" = [0-9]+' | grep -oE '[0-9]+' | head -1)
    battery_mah=${battery_mah:-4500}  # Fallback
    # Convert mAh to Wh using nominal voltage 11.4V (3-cell Li-ion)
    battery_wh=$(echo "scale=1; $battery_mah * 11.4 / 1000" | bc 2>/dev/null)
    battery_wh=${battery_wh:-52}  # Fallback to 52
    
    if [ -n "$real_power_w" ] && [ "$real_power_w" != "N/A" ]; then
        # Live efficiency (instant)
        at_100_hours=$(echo "scale=1; $battery_wh / $real_power_w" | bc 2>/dev/null)
        at_100_hours=${at_100_hours:-0}
        power_display=$(printf "%.1f" "$real_power_w")
        
        # Add to power history for 10-min average
        echo "$real_power_w" >> "$POWER_HISTORY_FILE"
        # Keep only last MAX_HISTORY_SAMPLES entries
        if [ -f "$POWER_HISTORY_FILE" ]; then
            tail -n "$MAX_HISTORY_SAMPLES" "$POWER_HISTORY_FILE" > "${POWER_HISTORY_FILE}.tmp"
            mv "${POWER_HISTORY_FILE}.tmp" "$POWER_HISTORY_FILE"
        fi
        
        # Calculate 10-minute average
        if [ -f "$POWER_HISTORY_FILE" ]; then
            sample_count=$(wc -l < "$POWER_HISTORY_FILE" | tr -d ' ')
            if [ "$sample_count" -gt 0 ]; then
                avg_power=$(awk '{ sum += $1; count++ } END { if (count > 0) printf "%.2f", sum/count; else print "0" }' "$POWER_HISTORY_FILE")
                avg_100_hours=$(echo "scale=1; $battery_wh / $avg_power" | bc 2>/dev/null)
                avg_100_hours=${avg_100_hours:-0}
                # Show time window (how many minutes of data we have)
                time_window_mins=$((sample_count / 60))
                [ "$time_window_mins" -lt 1 ] && time_window_mins=1
            else
                avg_100_hours="$at_100_hours"
                time_window_mins=0
            fi
        else
            avg_100_hours="$at_100_hours"
            time_window_mins=0
        fi
    else
        at_100_hours="N/A"
        power_display="N/A"
    fi
    
    # Battery header with AVERAGE efficiency rating (add clear-to-end-of-line to fix artifacts)
    printf "🔋 BATTERY:    %3d%%   " "$battery_pct"
    if [ "$is_charging" = "yes" ]; then
        printf "\033[32m(Charging)\033[0m\033[K\n"
    elif [ "$avg_100_hours" != "N/A" ] && [ -n "$avg_100_hours" ]; then
        avg_100_int=${avg_100_hours%.*}
        avg_100_int=${avg_100_int:-0}
        if [ "$avg_100_int" -ge 12 ]; then
            printf "(@100%%: %sh) ✅\033[K\n" "$avg_100_hours"
        elif [ "$avg_100_int" -ge 6 ]; then
            printf "\033[33m(@100%%: %sh)\033[0m\033[K\n" "$avg_100_hours"
        else
            printf "\033[31m(@100%%: %sh - heavy!)\033[0m\033[K\n" "$avg_100_hours"
        fi
    else
        printf "\033[K\n"
    fi
    printf "   ├─ Power Draw:  %s W\033[K\n" "$power_display"
    printf "   ├─ Time Left:   %s\033[K\n" "$time_remaining"
    # Show LIVE efficiency (instant reading)
    if [ "$at_100_hours" != "N/A" ]; then
        at_100_int=${at_100_hours%.*}
        if [ "$at_100_int" -ge 12 ]; then
            printf "   └─ Live @100%%: \033[32m%sh\033[0m\033[K\n" "$at_100_hours"
        elif [ "$at_100_int" -ge 6 ]; then
            printf "   └─ Live @100%%: \033[33m%sh\033[0m\033[K\n" "$at_100_hours"
        else
            printf "   └─ Live @100%%: \033[31m%sh\033[0m\033[K\n" "$at_100_hours"
        fi
    else
        printf "   └─ Live @100%%: N/A\033[K\n"
    fi
    
    echo ""
    
    # ==================== POWER SECTION ====================
    # Use real system power from SMC (already in real_power_w from battery section)
    if [ -n "$real_power_w" ] && [ "$real_power_w" != "N/A" ]; then
        total_sys_w=$(printf "%.2f" "$real_power_w")
        total_sys_mw=$(echo "$real_power_w * 1000" | bc 2>/dev/null | cut -d. -f1)
        total_sys_mw=${total_sys_mw:-0}
        # Calculate "Other" power (Display, SSD, WiFi, etc)
        soc_mw=$((cpu_watts + gpu_watts + ane_watts))
        other_mw=$((total_sys_mw - soc_mw))
        [ "$other_mw" -lt 0 ] && other_mw=0
    else
        total_sys_w="N/A"
        total_sys_mw=0
        other_mw=0
    fi
    
    printf "⚡ POWER:       %s W   " "$total_sys_w"
    printf "(Total System)\n"
    if [ "$e_cluster" -gt 0 ] || [ "$p_cluster" -gt 0 ]; then
        printf "   ├─ CPU:     %5d mW   [E: %d | P: %d]\n" "$cpu_watts" "$e_cluster" "$p_cluster"
    else
        printf "   ├─ CPU:     %5d mW\n" "$cpu_watts"
    fi
    printf "   ├─ GPU:     %5d mW\n" "$gpu_watts"
    printf "   ├─ ANE:     %5d mW\n" "$ane_watts"
    printf "   └─ Other:   %5d mW   (Display, SSD, WiFi, etc)\n" "$other_mw"
    
    echo ""
    
    # ==================== THERMAL SECTION ====================
    # Get all temperatures from our kim_temp_bin
    if [ -x "$script_dir/kim_temp_bin" ]; then
        cpu_temp=$("$script_dir/kim_temp_bin" cpu 2>/dev/null)
        gpu_temp=$("$script_dir/kim_temp_bin" gpu 2>/dev/null)
        mem_temp=$("$script_dir/kim_temp_bin" memory 2>/dev/null)
        ssd_temp=$("$script_dir/kim_temp_bin" ssd 2>/dev/null)
        batt_temp=$("$script_dir/kim_temp_bin" battery 2>/dev/null)
        hottest_temp=${cpu_temp:-0}
    else
        cpu_temp="N/A"; gpu_temp="N/A"; mem_temp="N/A"; ssd_temp="N/A"; batt_temp="N/A"
        hottest_temp="N/A"
    fi
    
    # Thermal header with hottest component
    printf "🌡️  THERMAL:    "
    if [ "$hottest_temp" != "N/A" ]; then
        hottest_int=${hottest_temp%.*}
        if [ "$hottest_int" -lt 60 ]; then
            printf "\033[32m%s°C\033[0m   (Target: <60°C) ✅\n" "$hottest_temp"
        elif [ "$hottest_int" -lt 80 ]; then
            printf "\033[33m%s°C\033[0m   (Target: <60°C)\n" "$hottest_temp"
        else
            printf "\033[31m%s°C\033[0m   (Target: <60°C - Throttling!)\n" "$hottest_temp"
        fi
    else
        printf "N/A\n"
    fi
    
    # Component breakdown
    printf "   ├─ CPU:      %6s°C\n" "${cpu_temp:-N/A}"
    printf "   ├─ GPU:      %6s°C\n" "${gpu_temp:-N/A}"
    printf "   ├─ Memory:   %6s°C\n" "${mem_temp:-N/A}"
    printf "   ├─ SSD:      %6s°C\n" "${ssd_temp:-N/A}"
    printf "   └─ Battery:  %6s°C\n" "${batt_temp:-N/A}"
    
    echo ""
    
    # ==================== MEMORY SECTION ====================
    printf "🧠 MEMORY:     %d%% free   " "$mem_pct"
    if [ "$mem_pct" -gt 30 ]; then
        printf "(Target: >30%%) ✅\n"
    elif [ "$mem_pct" -gt 15 ]; then
        printf "\033[33m(Target: >30%%)\033[0m\n"
    else
        printf "\033[31m(Target: >30%%)\033[0m\n"
    fi
    
    # ==================== WAKEUPS SECTION ====================
    printf "💤 WAKEUPS:    %5d/s   " "$wakeups"
    if [ "$wakeups" -lt 500 ]; then
        printf "(Target: <500/s) ✅\033[K\n"
    elif [ "$wakeups" -lt 1000 ]; then
        printf "\033[33m(Target: <500/s)\033[0m\033[K\n"
    else
        printf "\033[31m(Target: <500/s)\033[0m\033[K\n"
    fi
    
    echo ""
    echo "------------------------------------------------------------------------"
    
    # Process Attribution
    printf "%-35s | %10s | %10s\n" "TOP PROCESSES" "CPU ms/s" "WAKEUPS"
    echo "------------------------------------------------------------------------"
    
    # Process list parsing
    # Format: Name ID CPU_ms/s User% Deadlines(<2ms) Deadlines(2-5ms) Wakeups(Intr) Wakeups(PkgIdle)
    awk '
        /^Name/ { in_tasks=1; next }
        /^ALL_TASKS/ { exit }
        /^CPU Power/ { exit }
        in_tasks && NF >= 8 && $2 ~ /^[0-9]+$/ {
            name = $1
            cpu_ms = $3
            wkp = $7
            printf "%s|%s|%s\n", cpu_ms, wkp, name
        }
    ' "$TMP_FILE" | sort -t'|' -k1 -rn | head -8 | while IFS='|' read -r cpu wkp name; do
        # Only map system processes that have cryptic names
        # User apps should show their real name (no guessing!)
        case "$name" in
            # macOS System Processes (cryptic names that need translation)
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
            # Keep everything else as-is (real app names)
            *) friendly_name="$name" ;;
        esac
        
        # Truncate name
        name_short=$(printf "%.33s" "$friendly_name")
        
        # Color based on CPU usage
        if awk -v n="$cpu" 'BEGIN { exit (n > 50) ? 0 : 1 }' 2>/dev/null; then
            printf "\033[31m%-35s | %10s | %10s\033[0m\n" "$name_short" "$cpu" "$wkp"
        elif awk -v n="$cpu" 'BEGIN { exit (n > 20) ? 0 : 1 }' 2>/dev/null; then
            printf "\033[33m%-35s | %10s | %10s\033[0m\n" "$name_short" "$cpu" "$wkp"
        else
            printf "%-35s | %10s | %10s\n" "$name_short" "$cpu" "$wkp"
        fi
    done
    
    echo "------------------------------------------------------------------------"
    
    # BATTERY IMPACT ANALYSIS
    # Find high-wakeup offenders (>100 wakeups/sec, excluding system processes)
    battery_killers=$(awk '
        /^Name/ { in_tasks=1; next }
        /^ALL_TASKS/ { exit }
        /^CPU Power/ { exit }
        in_tasks && NF >= 8 && $2 ~ /^[0-9]+$/ {
            name = $1
            wkp = $7
            # Skip known system processes
            if (name ~ /^(kernel_task|WindowServer|powermetrics|launchd)$/) next
            # Only report high wakeup offenders
            if (wkp > 100) {
                printf "%s (%.0f/s)\n", name, wkp
            }
        }
    ' "$TMP_FILE")
    
    if [ -n "$battery_killers" ]; then
        printf "\n\033[33m🔋 BATTERY IMPACT:\033[0m Apps with high wakeups (>100/s):\n"
        echo "$battery_killers" | head -3 | while read -r line; do
            # Just show the line as-is - no guessing
            printf "   ⚠️  %s\n" "$line"
        done
        printf "   \033[2m→ These apps prevent deep sleep and drain battery faster\033[0m\n"
    fi
    
    echo "------------------------------------------------------------------------"
    printf "⏱️  Sampling every %dms | Ctrl+C to exit\n" "$SAMPLE_TIME"
    
    sleep 0.1
done
