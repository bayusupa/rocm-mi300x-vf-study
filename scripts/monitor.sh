#!/bin/bash
# rocm-mi300x-vf-monitor.sh
# Real-time GPU monitoring script for AMD MI300X VF on AMD Developer Cloud
# Usage: bash scripts/monitor.sh [interval_seconds]
#
# Outputs: GPU utilization, clock frequencies, VRAM usage, temperature, power draw
# Useful for observing clock behavior under sustained load

INTERVAL=${1:-5}  # Default refresh every 5 seconds
LOG_FILE="./data/monitor-$(date +%Y%m%d-%H%M%S).log"

echo "AMD MI300X VF Monitor"
echo "Platform: AMD Developer Cloud"
echo "ROCm Driver: $(cat /sys/module/amdgpu/version 2>/dev/null || echo 'unknown')"
echo "Logging to: $LOG_FILE"
echo "Refresh interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop."
echo ""

collect_snapshot() {
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # GPU utilization
    local GPU_USE=$(rocm-smi --showuse 2>/dev/null | grep "GPU use" | awk '{print $NF}')
    
    # Clock frequencies
    local SCLK=$(rocm-smi --showclocks 2>/dev/null | grep "sclk" | grep -oP '\d+Mhz' | head -1)
    local MCLK=$(rocm-smi --showclocks 2>/dev/null | grep "mclk" | grep -oP '\d+Mhz' | head -1)
    local FCLK=$(rocm-smi --showclocks 2>/dev/null | grep "fclk" | grep -oP '\d+Mhz' | head -1)
    
    # Temperature
    local TEMP_J=$(rocm-smi --showtemp 2>/dev/null | grep "junction" | grep -oP '\d+\.\d+')
    local TEMP_M=$(rocm-smi --showtemp 2>/dev/null | grep "memory" | grep -oP '\d+\.\d+')
    
    # Power
    local POWER=$(rocm-smi --showpower 2>/dev/null | grep "Socket" | grep -oP '\d+\.\d+')
    
    # VRAM
    local VRAM_USED=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Used Memory" | grep -oP '\d+' | head -1)
    local VRAM_TOTAL=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Total Memory" | grep -oP '\d+' | head -1)
    
    # VRAM percent
    local VRAM_PCT=0
    if [ -n "$VRAM_USED" ] && [ -n "$VRAM_TOTAL" ] && [ "$VRAM_TOTAL" -gt 0 ]; then
        VRAM_PCT=$(awk "BEGIN {printf \"%.1f\", ($VRAM_USED/$VRAM_TOTAL)*100}")
    fi

    # Display
    clear
    echo "===== AMD MI300X VF — Live Monitor ====="
    echo "Time        : $TIMESTAMP"
    echo "-----------------------------------------"
    echo "GPU Usage   : ${GPU_USE}"
    echo "Power Draw  : ${POWER}W / 750W"
    echo "-----------------------------------------"
    echo "sclk        : ${SCLK}  (max: 2100MHz)"
    echo "mclk        : ${MCLK}  (max: 1300MHz)"
    echo "fclk        : ${FCLK}  (max: 1800MHz)"
    echo "-----------------------------------------"
    echo "Temp (junc) : ${TEMP_J}°C"
    echo "Temp (mem)  : ${TEMP_M}°C"
    echo "-----------------------------------------"
    echo "VRAM Used   : ${VRAM_PCT}% (${VRAM_USED} / ${VRAM_TOTAL} bytes)"
    echo "-----------------------------------------"
    echo "Active GPU processes:"
    rocm-smi --showpids 2>/dev/null | grep -v "^=\|^$\|KFD\|PID" | head -5
    echo ""
    echo "Refresh every ${INTERVAL}s — Ctrl+C to stop — logging to $LOG_FILE"

    # Log to file
    echo "$TIMESTAMP | GPU:${GPU_USE} | Power:${POWER}W | sclk:${SCLK} | mclk:${MCLK} | fclk:${FCLK} | TempJ:${TEMP_J}C | TempM:${TEMP_M}C | VRAM:${VRAM_PCT}%" >> "$LOG_FILE"
}

# Create data directory if not exists
mkdir -p ./data

# Main loop
while true; do
    collect_snapshot
    sleep "$INTERVAL"
done
