# KIM_DEV_TOOL - Todo & Roadmap

## Current Status
- ✅ `kim_dev_tool.sh` - Interactive terminal monitor (working)
- ✅ `kim_temp_bin` - Rust binary for SMC sensor reading (working)

## Priority Tasks

### 1. LLM-Friendly JSON Output Mode
Create a simple command that outputs all metrics as JSON for LLM consumption.

**Goal:** `./kim_dev_tool.sh --json` or `./kim_metrics.sh` that outputs:
```json
{
  "battery": {
    "percent": 65,
    "charging": false,
    "power_draw_w": 5.2,
    "efficiency_at_100": 10.0
  },
  "power": {
    "total_w": 5.2,
    "cpu_mw": 400,
    "gpu_mw": 50,
    "ane_mw": 0,
    "other_mw": 4750
  },
  "thermal": {
    "cpu_c": 48.5,
    "gpu_c": 42.1,
    "memory_c": 38.2,
    "ssd_c": 41.0,
    "battery_c": 32.5
  },
  "memory": {
    "used_gb": 9.4,
    "total_gb": 16.0,
    "free_percent": 41
  },
  "wakeups": {
    "total_per_sec": 520,
    "target": 500
  },
  "top_processes": [
    {"name": "Safari", "cpu_ms": 120.5, "wakeups": 15.2},
    {"name": "macOS Kernel", "cpu_ms": 45.0, "wakeups": 450.0}
  ]
}
```

### 2. Improve Memory Display
Current: `🧠 MEMORY: 41% free (Target: >30%) ✅`
Better: `🧠 MEMORY: 9.4 GB / 16 GB (41% free) ✅`

### 3. Add Contextual Hints
- When charging: Show "(Normal when charging)" for high power draw
- When updating: Detect software updates and show "(System updating)"

### 4. Process Name Mapping
- Create a mapping file for common process → friendly name
- Make it user-extensible

## Nice to Have

### 5. Historical Tracking
- Log metrics to a file over time
- Show trends (power going up/down)

### 6. Alerts Mode
- Only output when something is wrong
- Useful for background monitoring

### 7. Web Dashboard
- Simple local web page showing metrics
- Real-time updates

## File Structure
```
Apple Silicon Benchmarking tools/
├── kim_dev_tool.sh      # Main interactive monitor
├── kim_metrics.sh       # (TODO) Simple JSON output for LLM
├── kim_temp_bin         # Compiled Rust binary for SMC
├── kim_temp/            # Rust source code
│   ├── Cargo.toml
│   └── src/main.rs
├── README.md            # Documentation
└── TODO.md              # This file
```
