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

# ==============================================================================
# CLEANUP & SAFETY
# ==============================================================================
cleanup() {
    rm -f "$TMP_FILE"
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

# Get thermal state from powermetrics
get_thermal() {
    local pressure
    pressure=$(grep -E "Current pressure level:" "$TMP_FILE" 2>/dev/null | awk -F': ' '{print $2}')
    
    if [ -z "$pressure" ]; then
        echo "N/A"
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
    
    # 7. RENDER UI
    clear
    echo "========================================================================"
    echo "           🔬 KIM_DEV_TOOL: Apple Silicon Truth Monitor"
    echo "========================================================================"
    
    # Power Section
    printf "⚡ POWER:       %5d mW   " "$total_watts"
    printf "(Base: %d | Δ " "$base_watts"
    if [ "$watts_delta" -gt 0 ]; then
        printf "\033[33m+%d\033[0m)\n" "$watts_delta"
    elif [ "$watts_delta" -lt 0 ]; then
        printf "\033[32m%d\033[0m)\n" "$watts_delta"
    else
        printf "0)\n"
    fi
    
    # CPU breakdown with E/P if available
    if [ "$e_cluster" -gt 0 ] || [ "$p_cluster" -gt 0 ]; then
        printf "   ├─ CPU:     %5d mW   [E: %d | P: %d]\n" "$cpu_watts" "$e_cluster" "$p_cluster"
    else
        printf "   ├─ CPU:     %5d mW\n" "$cpu_watts"
    fi
    printf "   ├─ GPU:     %5d mW\n" "$gpu_watts"
    printf "   └─ ANE:     %5d mW\n" "$ane_watts"
    
    echo ""
    
    # Memory Pressure
    case "$mem_state" in
        "Normal")   printf "🧠 MEMORY:     \033[32m%-8s\033[0m (%d%% avail)\n" "$mem_state" "$mem_pct" ;;
        "Warning")  printf "🧠 MEMORY:     \033[33m%-8s\033[0m (%d%% avail)\n" "$mem_state" "$mem_pct" ;;
        "Critical") printf "🧠 MEMORY:     \033[31m%-8s\033[0m (%d%% avail)\n" "$mem_state" "$mem_pct" ;;
        *)          printf "🧠 MEMORY:     %-8s\n" "$mem_state" ;;
    esac
    
    # Thermal
    printf "🌡️  THERMAL:    %s\n" "$thermal"
    
    # Wakeups
    printf "💤 WAKEUPS:    %5d /s\n" "$wakeups"
    
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
        # Truncate name
        name_short=$(printf "%.33s" "$name")
        
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
            printf "   ⚠️  %s\n" "$line"
        done
        printf "   \033[2m→ These apps prevent deep sleep and drain battery faster\033[0m\n"
    fi
    
    echo "------------------------------------------------------------------------"
    printf "⏱️  Sampling every %dms | Ctrl+C to exit\n" "$SAMPLE_TIME"
    
    sleep 0.1
done
