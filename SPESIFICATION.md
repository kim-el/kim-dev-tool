# Project Specification: Apple Silicon Benchmarking Tools

## Overview
A high-efficiency benchmarking tool for Apple Silicon, focusing on power (Watts), thermal metrics, and system wakeups.

## Components
- `kim_temp_bin`: A Rust-based binary that reads SMC sensors and `powermetrics`.
  - `kim_temp_bin stream`: Direct JSON stream for the dashboard.
  - `kim_temp_bin json`: One-shot JSON snapshot for LLMs.
- `kim_dev_tool.sh`: A Bash script providing a human-readable dashboard by parsing the stream from `kim_temp_bin`.
- `tool.json`: Metadata for LLM integration.

## Usage
- `sudo ./kim_dev_tool.sh`: Real-time monitoring UI.
- `./kim_temp_bin json`: Machine-readable snapshot.

## Changes
- **2026-01-07**: Added `check` script to unify human and LLM commands.
  - `check temp`: Runs the human-readable dashboard.
  - `check delta`: Runs the LLM-readable JSON snapshot.
  - **Completed**: Created `/Users/kimen/Projects/Apple-Silicon-Benchmarking-tools/check` and made it executable.
- **2026-01-07T02:22:00+08:00**: Task completed. Unified `check` entry point is now live.
- **2026-01-09**: Fixed Observer Effect & Added M4 Support.
  - **Issue**: `powermetrics` was running every second, causing high battery drain and skewed readings (observer effect).
  - **Optimization**: Implemented "Hybrid Polling". 
    - Fast Path (1s): Read SMC hardware sensors directly. Zero subprocess overhead.
    - Slow Path (5s): Run `powermetrics`, `pmset`, `vm_stat` to update process list and battery stats.
  - **M4 Support**: Identified and verified main power sensors. After extensive stress testing, the tool was updated to use hardcoded keys for stability: `PP0b` for CPU (Main Cluster) and `PP1b` for GPU. Dynamic calibration was disabled for these keys to prevent idle-noise mismatch.
  - **Verification**: CPU verified at ~12W load; GPU verified at ~6W load. Reading accuracy matches `powermetrics` within 10%.
- **2026-01-10**: Fixed Battery Capacity Source.
  - **Issue**: "Live @ 100%" used Factory Design Capacity, overestimating runtime on degraded batteries.
  - **Fix**: Updated `kim_temp_bin` to prioritize `NominalChargeCapacity` (Real Health) over `DesignCapacity`.

## Known Issues
- **2026-01-09**: Dynamic Calibration requires `sudo` (prompted at startup) because it runs a one-time `powermetrics` baseline.
