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
  - **M4 Support**: Added `calibrate_cpu_gpu_keys` to auto-detect the correct power sensors. On M4, it identified `PZD1` or `Pb0f` instead of the old `PP0b` standard.
  - **Verification**: CPU readings verified (400mW idle, 11W under 4-core load on M4).
- **2026-01-10**: Fixed Battery Capacity Source.
  - **Issue**: "Live @ 100%" used Factory Design Capacity, overestimating runtime on degraded batteries.
  - **Fix**: Updated `kim_temp_bin` to prioritize `NominalChargeCapacity` (Real Health) over `DesignCapacity`.

## Known Issues
- **2026-01-09**: Dynamic Calibration requires `sudo` (prompted at startup) because it runs a one-time `powermetrics` baseline.
