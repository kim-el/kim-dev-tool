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
- **2026-01-09**: Verified accurate Display Power measurement.
  - **Findings**: The screen power is on the Main System Rail (`PSTR`) but not the Package Rail (`PHPS`).
  - **Formula**: `Display Power = (System_Total_PSTR - CPU - GPU - ANE - Memory).max(0)`.
  - **Verification**: User test confirmed `Est_Display` jumped by ~10W when toggling brightness to MAX, while CPU/GPU remained idle.
  - **Implementation**: Updated `kim_temp_bin` to use this formula for `display_w`.

## Known Issues
- **2026-01-08**: User reported `check delta` returning "check temp".
  - **Investigation**: Code and script appeared correct.
  - **Action**: Recompiled `kim_temp_bin` from source to ensure integrity.
  - **Status**: Verified working in local environment.
